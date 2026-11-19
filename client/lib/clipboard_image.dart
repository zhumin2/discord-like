/// 跨平台剪贴板图片访问（条件导出，无平台插件，见 AGENTS.md 坑 8）：
/// - Web：document.onPaste + navigator.clipboard
/// - Windows：原生通道 chord/file（CF_DIB 读取 / 写入）
/// - Android：粘贴暂不支持（返回空实现，发图仍可用 📎 附件）
///
/// 注意：本文件只能放 export，不能放同名实现——否则本地声明会覆盖导出，
/// 运行时抛 "Unsupported operation: replaced by conditional export"。
export 'clipboard_common.dart' show Unregister;
export 'clipboard_image_io.dart' if (dart.library.html) 'clipboard_image_web.dart';
