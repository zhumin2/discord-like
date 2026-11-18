import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 返回图片磁盘缓存目录（不存在则创建）。失败返回 null（只走内存/网络）。
/// - Windows：%LOCALAPPDATA%\Chord\cache\images
/// - Android：应用私有目录 cache/images（路径经 chord/file.storagePath 通道）
Future<String?> cacheDir() async {
  try {
    if (Platform.isAndroid) {
      final path = await const MethodChannel('chord/file')
          .invokeMethod<String>('storagePath');
      if (path == null || path.isEmpty) return null;
      final dir = Directory('$path/cache/images');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir.path;
    }
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final dirPath = (localAppData != null && localAppData.isNotEmpty)
        ? '$localAppData\Chord\cache\images'
        : '${File(Platform.resolvedExecutable).parent.path}\cache\images';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> readCacheFile(String path) async {
  try {
    final f = File(path);
    if (f.existsSync()) return f.readAsBytesSync();
  } catch (_) {}
  return null;
}

Future<void> writeCacheFile(String path, Uint8List bytes) async {
  try {
    await File(path).writeAsBytes(bytes, flush: true);
  } catch (_) {}
}

Future<void> deleteCacheDir(String dir) async {
  try {
    final d = Directory(dir);
    if (d.existsSync()) d.deleteSync(recursive: true);
  } catch (_) {}
}
