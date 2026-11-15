import 'dart:convert';

import 'package:web/web.dart' as web;

/// Web 平台实现：localStorage。
/// 兼容迁移：读取旧版 SharedPreferences 的 `flutter.<key>` 键（值经 JSON 编码）。
class KeyValueStore {
  static String? getString(String key) {
    // 旧键迁移（SharedPreferences 在 web 上以 flutter.<key> 存储且值带 JSON 引号）
    final legacy = web.window.localStorage.getItem('flutter.$key');
    if (legacy != null) {
      try {
        final decoded = jsonDecode(legacy);
        if (decoded is String) {
          web.window.localStorage.setItem(key, decoded);
          web.window.localStorage.removeItem('flutter.$key');
          return decoded;
        }
      } catch (_) {
        // 非 JSON 字符串，视为损坏数据
        web.window.localStorage.removeItem('flutter.$key');
      }
    }
    return web.window.localStorage.getItem(key);
  }

  static Future<void> setString(String key, String? value) async {
    if (value == null) {
      web.window.localStorage.removeItem(key);
      web.window.localStorage.removeItem('flutter.$key');
    } else {
      web.window.localStorage.setItem(key, value);
    }
  }
}
