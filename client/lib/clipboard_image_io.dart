import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'clipboard_common.dart';

const _ch = MethodChannel('chord/file');

// 一个平台通道只能有一个 method call handler，而图片粘贴与文件拖放都要
// 注册监听（Composer 里同时启用）——这里做多路分发，避免后注册的把先注册的顶掉。
final _imageHandlers = <void Function(Uint8List bytes, String mime)>{};
final _fileHandlers = <DroppedFilesHandler>{};
bool _handlerInstalled = false;

void _ensureHandler() {
  if (_handlerInstalled) return;
  _handlerInstalled = true;
  _ch.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onClipboardImage':
        final decoded = _decodeImagePayload(call.arguments);
        if (decoded == null) return null;
        for (final h in List.of(_imageHandlers)) {
          h(decoded.$1, 'image/png');
        }
        return null;
      case 'onClipboardFiles':
      case 'onDroppedFiles':
        final files = await _filesFromPayload(call.arguments);
        if (files.isEmpty) return null;
        for (final h in List.of(_fileHandlers)) {
          h(files);
        }
        return null;
    }
    return null;
  });
}

/// 原生推送的 RGBA 像素 → PNG 字节。
(Uint8List, String)? _decodeImagePayload(dynamic args) {
  if (args is! Map) return null;
  final rgba = args['data'] as Uint8List?;
  final w = args['width'] as int? ?? 0;
  final h = args['height'] as int? ?? 0;
  if (rgba == null || rgba.isEmpty || w <= 0 || h <= 0) return null;
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  return (Uint8List.fromList(img.encodePng(image)), 'image/png');
}

/// [{path, name}] → 读取字节后的文件列表（读取失败的条目跳过）。
Future<List<DroppedFile>> _filesFromPayload(dynamic args) async {
  final out = <DroppedFile>[];
  if (args is! List) return out;
  for (final e in args) {
    if (e is! Map) continue;
    final path = e['path'] as String?;
    if (path == null || path.isEmpty) continue;
    final name = (e['name'] as String?) ??
        path.split(Platform.pathSeparator).last;
    try {
      out.add(DroppedFile(name, await File(path).readAsBytes()));
    } catch (_) {
      // 文件被占用/已删除：忽略
    }
  }
  return out;
}

/// IO 平台（Windows 桌面 / Android）：
/// - Windows：原生在 WM_KEYDOWN 拦截「Ctrl+V 且剪贴板为图片」时主动回调
///   onClipboardImage（参数 RGBA 原始像素 + 宽高），这里编码为 PNG 再交给上层；
///   剪贴板是文件（CF_HDROP）时回调 onClipboardFiles；文件拖进窗口时回调
///   onDroppedFiles。复制图片走 copyImage 方法（GDI+ 解码 → 剪贴板）。
/// - Android：暂不支持（返回空实现；发图用 📎 附件）。
Unregister registerPasteImage(void Function(Uint8List bytes, String mime) onImage) {
  if (!Platform.isWindows) return () {};
  _imageHandlers.add(onImage);
  _ensureHandler();
  return () => _imageHandlers.remove(onImage);
}

/// 监听「粘贴文件」（资源管理器 Ctrl+C → 应用内 Ctrl+V）与「拖放文件」。
Unregister registerDroppedFiles(DroppedFilesHandler onFiles) {
  if (!Platform.isWindows) return () {};
  _fileHandlers.add(onFiles);
  _ensureHandler();
  return () => _fileHandlers.remove(onFiles);
}

Future<bool> copyImageToClipboard(Uint8List bytes) async {
  if (!Platform.isWindows) return false;
  try {
    // 原生侧不做解码（无图像库）；Dart 解码成 RGBA + 宽高，原生拼 DIB 写剪贴板
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return false;
    final converted = decoded.convert(numChannels: 4);
    final rgba = converted.getBytes(order: img.ChannelOrder.rgba);
    final r = await _ch.invokeMethod<bool>('copyImage', {
      'data': rgba,
      'width': converted.width,
      'height': converted.height,
    });
    return r ?? false;
  } catch (_) {
    return false;
  }
}

/// 主动读取系统剪贴板里的图片（Windows）；返回 PNG 字节，没有图片返回 null。
/// 作为 Ctrl+V 的兜底路径：键盘焦点在 Flutter 子窗口时，顶层窗口收不到 WM_KEYDOWN。
Future<Uint8List?> readClipboardImage() async {
  if (!Platform.isWindows) return null;
  try {
    final args = await _ch.invokeMethod<Map>('readClipboardImage');
    if (args == null) return null;
    final decoded = _decodeImagePayload(args);
    return decoded?.$1;
  } catch (_) {
    return null;
  }
}

/// 主动读取系统剪贴板里的文件（Windows CF_HDROP）；没有文件返回空列表。
Future<List<DroppedFile>> readClipboardFiles() async {
  if (!Platform.isWindows) return const [];
  try {
    final r = await _ch.invokeMethod<List>('readClipboardFiles');
    if (r == null) return const [];
    return await _filesFromPayload(r);
  } catch (_) {
    return const [];
  }
}
