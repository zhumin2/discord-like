import 'dart:convert';
import 'dart:io';

/// IO 平台实现：JSON 文件持久化（不依赖任何平台插件）。
class KeyValueStore {
  static File? _fileFor() {
    try {
      final appData = Platform.environment['APPDATA'];
      final dir = Directory(
          appData != null && appData.isNotEmpty ? '$appData\\Chord' : '${File(Platform.resolvedExecutable).parent.path}\\data_user');
      dir.createSync(recursive: true);
      return File('${dir.path}\\storage.json');
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _read() {
    final f = _fileFor();
    try {
      if (f != null && f.existsSync()) {
        final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        return raw.map((k, v) => MapEntry(k, v as String));
      }
    } catch (_) {}
    return {};
  }

  static String? getString(String key) => _read()[key];

  static Future<void> setString(String key, String? value) async {
    final m = _read();
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    final f = _fileFor();
    try {
      await f?.writeAsString(jsonEncode(m));
    } catch (_) {}
  }
}
