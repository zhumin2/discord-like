import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'clipboard_common.dart';

const _ch = MethodChannel('chord/file');

/// IO 平台（Windows 桌面 / Android）：
/// - Windows：原生在 WM_KEYDOWN 拦截「Ctrl+V 且剪贴板为图片」时主动回调
///   onClipboardImage（参数 RGBA 原始像素 + 宽高），这里编码为 PNG 再交给上层；
///   复制图片走 copyImage 方法（GDI+ 解码 → 剪贴板）。
/// - Android：暂不支持（返回空实现；发图用 📎 附件）。
Unregister registerPasteImage(void Function(Uint8List bytes, String mime) onImage) {
  if (!Platform.isWindows) return () {};
  _ch.setMethodCallHandler((call) async {
    if (call.method == 'onClipboardImage') {
      final args = call.arguments as Map?;
      final rgba = (args?['data'] as Uint8List?) ?? Uint8List(0);
      final w = (args?['width'] as int?) ?? 0;
      final h = (args?['height'] as int?) ?? 0;
      if (rgba.isEmpty || w <= 0 || h <= 0) return null;
      final image = img.Image.fromBytes(
        width: w, height: h, bytes: rgba.buffer, numChannels: 4,
      );
      onImage(Uint8List.fromList(img.encodePng(image)), 'image/png');
    }
    return null;
  });
  return () { _ch.setMethodCallHandler(null); };
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
    }) as bool?;
    return r ?? false;
  } catch (_) {
    return false;
  }
}
