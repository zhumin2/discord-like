import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// IO 平台实现：JSON 文件持久化（不依赖任何平台插件）。
/// - Windows：`%APPDATA%\Chord\storage.json`
/// - Android：应用私有目录 `filesDir/storage/storage.json`，路径经既有原生通道
///   `chord/file` 的 `storagePath` 方法获取（Android 上 %APPDATA% 不存在，
///   resolvedExecutable 所在目录只读，原实现会静默失败 → 登录态每次启动丢失）。
class KeyValueStore {
  static const MethodChannel _channel = MethodChannel('chord/file');
  static String? _androidDir;

  static bool get _isAndroid => Platform.isAndroid;

  static Future<String?> _fileFor() async {
    try {
      if (_isAndroid) {
        _androidDir ??= await _channel.invokeMethod<String>('storagePath');
        final dir = _androidDir;
        if (dir == null || dir.isEmpty) return null;
        return '${dir}/storage.json';
      }
      final appData = Platform.environment['APPDATA'];
      final dirPath = (appData != null && appData.isNotEmpty)
          ? '$appData/Chord'
          : '${File(Platform.resolvedExecutable).parent.path}/data_user';
      return '$dirPath/storage.json';
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> _read() async {
    try {
      final path = await _fileFor();
      if (path != null) {
        final f = File(path);
        if (f.existsSync()) {
          final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          return raw.map((k, v) => MapEntry(k, v as String));
        }
      }
    } catch (_) {}
    return {};
  }

  static Future<String?> getString(String key) async => (await _read())[key];

  static Future<void> setString(String key, String? value) async {
    final m = await _read();
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    try {
      final path = await _fileFor();
      if (path != null) {
        await File(path).writeAsString(jsonEncode(m), flush: true);
      }
    } catch (_) {}
  }
}
