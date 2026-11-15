/// 跨平台键值存储的条件导出入口：
/// - IO（Windows 桌面等）：JSON 文件，位于 %APPDATA%\Chord\storage.json
/// - Web：localStorage（并自动迁移旧版 SharedPreferences 的 flutter.<key> 键）
export 'storage_io.dart' if (dart.library.html) 'storage_web.dart';
