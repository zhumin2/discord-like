import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// IO 平台（Windows/Android）：通过原生平台通道 `chord/file` 选文件。
/// 通道实现：Windows = runner C++（GetOpenFileNameW），Android = MainActivity Kotlin（SAF）。
class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

/// 返回选中文件的字节与显示名；用户取消返回 null。
Future<PickedFile?> pickFile({bool imagesOnly = false}) async {
  const ch = MethodChannel('chord/file');
  try {
    final r = await ch
        .invokeMethod<Map<dynamic, dynamic>>('pickFile', {'imagesOnly': imagesOnly});
    if (r == null) return null;
    final path = r['path'] as String;
    final name = (r['name'] as String?) ??
        path.split(Platform.pathSeparator).last;
    final bytes = await File(path).readAsBytes();
    return PickedFile(name, bytes);
  } on PlatformException catch (e) {
    if (e.code == 'cancel') return null;
    rethrow;
  }
}
