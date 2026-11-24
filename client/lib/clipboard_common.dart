import 'dart:typed_data';

/// 剪贴板/拖放的跨平台共享声明（条件导入的两个实现都依赖它）。

typedef Unregister = void Function();

/// 拖入 / 粘贴进来的文件（照片以外也支持任意附件）。
/// IO 端（Windows/Android）从路径读入字节后统一填充 [bytes]。
class DroppedFile {
  final String name;
  final Uint8List bytes;
  const DroppedFile(this.name, this.bytes);
}

typedef DroppedFilesHandler = void Function(List<DroppedFile> files);
