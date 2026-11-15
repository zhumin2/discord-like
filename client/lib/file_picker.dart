/// 跨平台文件选择的条件导出入口（刻意不依赖任何平台插件，见 AGENTS.md 踩坑 8）：
/// - IO（Windows 桌面 / Android）：原生平台通道 `chord/file`
///   （Windows = runner C++ GetOpenFileNameW；Android = MainActivity Kotlin SAF）
/// - Web：<input type="file">（dart:html）
export 'file_picker_io.dart' if (dart.library.html) 'file_picker_web.dart';
