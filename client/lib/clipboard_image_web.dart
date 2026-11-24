// Web 平台：粘贴由 index.html 的 JS 监听（FileReader → dataURL → 自定义事件），
// 复制用 navigator.clipboard + ClipboardItem。
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'clipboard_common.dart';

/// 监听 index.html 派发的 chord-paste-image 事件，解出图片字节后回调。
Unregister registerPasteImage(void Function(Uint8List bytes, String mime) onImage) {
  final sub = html.window.on['chord-paste-image'].listen((html.Event raw) {
    // index.html 直接把 FileReader 的 dataURL 放在 detail（字符串）
    final dataUrl = (raw as html.CustomEvent).detail?.toString();
    if (dataUrl == null) return;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return;
    final mime = dataUrl.substring(5, comma > 5 ? comma : dataUrl.length)
        .split(';')
        .first;
    try {
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      onImage(bytes, mime.isEmpty ? 'image/png' : mime);
    } catch (_) {}
  });
  return sub.cancel;
}

/// 监听「粘贴文件」（资源管理器 Ctrl+C → 页面 Ctrl+V）与「拖放文件」：
/// index.html 把每个文件读成 dataURL，detail 是 JSON 数组字符串。
Unregister registerDroppedFiles(DroppedFilesHandler onFiles) {
  final subs = <StreamSubscription>[];
  for (final eventName in const ['chord-paste-files', 'chord-drop-files']) {
    subs.add(html.window.on[eventName].listen((html.Event raw) {
      final detail = (raw as html.CustomEvent).detail?.toString();
      if (detail == null || detail.isEmpty) return;
      List<dynamic> list;
      try {
        list = jsonDecode(detail) as List<dynamic>;
      } catch (_) {
        return;
      }
      final files = <DroppedFile>[];
      for (final e in list) {
        if (e is! Map) continue;
        final dataUrl = e['dataUrl']?.toString() ?? '';
        final comma = dataUrl.indexOf(',');
        if (comma < 0) continue;
        try {
          files.add(DroppedFile(
              e['name']?.toString() ?? 'file',
              base64Decode(dataUrl.substring(comma + 1))));
        } catch (_) {}
      }
      if (files.isNotEmpty) onFiles(files);
    }));
  }
  return () {
    for (final s in subs) {
      s.cancel();
    }
  };
}

/// 复制图片到剪贴板：转 PNG 后经 ClipboardItem 写入（Chrome 只接受 image/png）。
Future<bool> copyImageToClipboard(Uint8List bytes) async {
  try {
    Uint8List png = bytes;
    final isPng = bytes.length > 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    if (!isPng) {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return false;
      png = Uint8List.fromList(img.encodePng(decoded));
    }
    final ctor = js.context['ClipboardItem'] as js.JsFunction?;
    final nav = js.context['navigator'] as js.JsObject?;
    if (ctor == null || nav == null) return false;
    final clipboard = nav['clipboard'] as js.JsObject?;
    if (clipboard == null) return false;
    final blob = html.Blob([png], 'image/png');
    final item = js.JsObject(ctor, [
      js.JsObject.jsify({'image/png': blob})
    ]);
    // 在有用户手势（右键菜单点击）时 Chrome 允许直接写入
    clipboard.callMethod('write', [js.JsObject.jsify([item])]);
    return true;
  } catch (_) {
    return false;
  }
}

/// Web 上不支持主动读取剪贴板图片（浏览器安全限制），返回 null。
/// 粘贴由 index.html 的 paste 监听完成后台 bridge 送达。
Future<Uint8List?> readClipboardImage() async => null;

/// Web 上不支持主动读取剪贴板文件（浏览器安全限制）；粘贴/拖放走事件桥。
Future<List<DroppedFile>> readClipboardFiles() async => const [];
