// Web 平台：<input type="file">，无需任何插件。
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'file_picker_io.dart' show PickedFile;

/// 返回选中文件的字节与显示名；用户取消返回 null。
Future<PickedFile?> pickFile({bool imagesOnly = false}) async {
  final input = html.InputElement(type: 'file')
    ..accept = imagesOnly ? 'image/*' : '*/*';
  input.click(); // 由按钮点击事件链调用，满足浏览器手势要求
  final change = await input.onChange.first;
  final f = change.target as html.FileInputElement;
  final file = f.files?.first;
  if (file == null) return null;

  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoadEnd.first;
  final bytes = Uint8List.fromList((reader.result as ByteBuffer).asUint8List());
  return PickedFile(file.name, bytes);
}
