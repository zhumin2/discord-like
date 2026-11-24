// Web 平台：<input type="file">，无需任何插件。
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'file_picker_io.dart' show PickedFile;

/// 返回选中文件的字节与显示名；用户取消返回 null。
///
/// 取消检测（v1.4.1 反馈 12）：用户点「取消」时不会触发 change 事件，
/// 旧实现 `await input.onChange.first` 会永远挂起（转圈不结束）。
/// 这里三重兜底：① 浏览器 cancel 事件（Chrome 113+）；② 窗口重新获得焦点
/// 后短暂等待仍无 change → 视为取消（老浏览器）；③ 完成一次后立即清理。
Future<PickedFile?> pickFile({bool imagesOnly = false}) async {
  final input = html.FileUploadInputElement()
    ..accept = imagesOnly ? 'image/*' : '*/*'
    ..style.display = 'none';
  // 挂到 DOM 上，部分浏览器只对文档内元素派发 cancel 事件
  html.document.body?.append(input);

  final completer = Completer<PickedFile?>();
  var selected = false; // 已收到 change（正在读字节），焦点兜底不能再判取消
  StreamSubscription? changeSub;
  late final html.EventListener cancelListener;
  html.EventListener? focusListener;

  void cleanup() {
    changeSub?.cancel();
    input.removeEventListener('cancel', cancelListener);
    if (focusListener != null) {
      html.window.removeEventListener('focus', focusListener);
    }
    input.remove();
  }

  void finish(PickedFile? file) {
    if (completer.isCompleted) return;
    cleanup();
    completer.complete(file);
  }

  cancelListener = (html.Event _) => finish(null);
  input.addEventListener('cancel', cancelListener);

  changeSub = input.onChange.listen((_) async {
    selected = true;
    try {
      // 注意：用户取消时有些浏览器会派发 change 但 files 为空列表，
      // 直接 .first 会抛 "Bad state: No element"（表现为"点取消弹报错"）。
      final files = input.files;
      if (files == null || files.isEmpty) {
        finish(null);
        return;
      }
      final file = files.first;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoadEnd.first;
      final bytes = (reader.result as ByteBuffer).asUint8List();
      finish(PickedFile(file.name, bytes));
    } catch (_) {
      finish(null);
    }
  });

  // 老浏览器兜底：对话框关闭后窗口重新获得焦点；稍等仍无 change 即取消
  focusListener = (html.Event _) {
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!completer.isCompleted && !selected) finish(null);
    });
  };
  html.window.addEventListener('focus', focusListener);

  input.click(); // 由按钮点击事件链调用，满足浏览器手势要求
  return completer.future;
}
