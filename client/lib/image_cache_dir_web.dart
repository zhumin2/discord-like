import 'dart:typed_data';

/// Web 端没有文件系统：磁盘缓存交给浏览器 HTTP 缓存
/// （/uploads/* 为 immutable 长缓存），这里全部返回 null。
Future<String?> cacheDir() async => null;

Future<Uint8List?> readCacheFile(String path) async => null;

Future<void> writeCacheFile(String path, Uint8List bytes) async {}

Future<void> deleteCacheDir(String dir) async {}
