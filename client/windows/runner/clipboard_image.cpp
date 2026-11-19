// 剪贴板图片（Windows 原生实现，无插件）：
// - 粘贴：Ctrl+V 时若剪贴板含 CF_DIB，解码成 RGBA 原始像素经 chord/file 通道
//   以 onClipboardImage 回调给 Dart（Dart 侧编码 PNG / 走压缩上传管线）
// - 复制：Dart 传入 RGBA + 宽高，这里拼 BITMAPINFOHEADER + 像素写入 CF_DIB
// 该文件含中文注释，必须 UTF-8 BOM + runner CMakeLists 已加 /utf-8（见 AGENTS.md 坑 4）。
#include "clipboard_image.h"

#include <windows.h>

#include <cstring>

namespace clipboard_image {

bool CopyRgbaToClipboard(const std::vector<uint8_t>& rgba, int width, int height) {
  if (rgba.empty() || width <= 0 || height <= 0) return false;
  if (rgba.size() < static_cast<size_t>(width) * height * 4) return false;

  // DIB 像素按 4 字节对齐，行序自下而上（bottom-up）
  const int row_bytes = width * 3;
  const int stride = (row_bytes + 3) & ~3;
  const int image_size = stride * height;
  const int header_size = sizeof(BITMAPINFOHEADER);
  const size_t total = static_cast<size_t>(header_size) + image_size;

  HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, total);
  if (mem == nullptr) return false;
  auto* base = static_cast<uint8_t*>(GlobalLock(mem));
  if (base == nullptr) {
    GlobalFree(mem);
    return false;
  }
  BITMAPINFOHEADER bih{};
  bih.biSize = header_size;
  bih.biWidth = width;
  bih.biHeight = height;  // 正数 = bottom-up
  bih.biPlanes = 1;
  bih.biBitCount = 24;
  bih.biCompression = BI_RGB;
  bih.biSizeImage = image_size;
  std::memcpy(base, &bih, header_size);

  uint8_t* pixels = base + header_size;
  for (int y = 0; y < height; ++y) {
    const uint8_t* src_row = rgba.data() + static_cast<size_t>(y) * width * 4;
    uint8_t* dst_row = pixels + static_cast<size_t>(height - 1 - y) * stride;
    for (int x = 0; x < width; ++x) {
      // RGBA → BGR（24bpp DIB 无 alpha 通道）
      dst_row[x * 3 + 0] = src_row[x * 4 + 2];
      dst_row[x * 3 + 1] = src_row[x * 4 + 1];
      dst_row[x * 3 + 2] = src_row[x * 4 + 0];
    }
  }
  GlobalUnlock(mem);

  if (!OpenClipboard(nullptr)) {
    GlobalFree(mem);
    return false;
  }
  EmptyClipboard();
  const bool ok = SetClipboardData(CF_DIB, mem) != nullptr;
  CloseClipboard();
  if (!ok) GlobalFree(mem);  // 成功后所有权归系统，不能释放
  return ok;
}

bool ReadClipboardRgba(std::vector<uint8_t>* out_rgba, int* out_width,
                       int* out_height) {
  if (!IsClipboardFormatAvailable(CF_DIB)) return false;
  if (!OpenClipboard(nullptr)) return false;

  HANDLE handle = GetClipboardData(CF_DIB);
  if (handle == nullptr) {
    CloseClipboard();
    return false;
  }
  auto* base = static_cast<uint8_t*>(GlobalLock(handle));
  if (base == nullptr) {
    CloseClipboard();
    return false;
  }

  BITMAPINFOHEADER bih{};
  std::memcpy(&bih, base, sizeof(bih));

  bool ok = false;
  const int width = bih.biWidth;
  const int height = bih.biHeight < 0 ? -bih.biHeight : bih.biHeight;
  const bool bottom_up = bih.biHeight > 0;

  if ((bih.biBitCount == 32 || bih.biBitCount == 24) && width > 0 &&
      width < 20000 && height > 0 && height < 20000 &&
      bih.biCompression == BI_RGB) {
    const int bpp = bih.biBitCount / 8;
    const int stride = ((width * bpp) + 3) & ~3;
    out_rgba->resize(static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
      const int src_y = bottom_up ? (height - 1 - y) : y;
      const uint8_t* src_row = base + sizeof(BITMAPINFOHEADER) +
                               static_cast<size_t>(src_y) * stride;
      uint8_t* dst_row = out_rgba->data() + static_cast<size_t>(y) * width * 4;
      for (int x = 0; x < width; ++x) {
        const uint8_t b = src_row[x * bpp + 0];
        const uint8_t g = src_row[x * bpp + 1];
        const uint8_t r = src_row[x * bpp + 2];
        const uint8_t a = bpp == 4 ? src_row[x * 4 + 3] : 255;
        dst_row[x * 4 + 0] = r;
        dst_row[x * 4 + 1] = g;
        dst_row[x * 4 + 2] = b;
        dst_row[x * 4 + 3] = a;
      }
    }
    *out_width = width;
    *out_height = height;
    ok = true;
  }

  GlobalUnlock(handle);
  CloseClipboard();
  return ok;
}

}  // namespace clipboard_image
