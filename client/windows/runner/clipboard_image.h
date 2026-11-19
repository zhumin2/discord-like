// 剪贴板图片（Windows 原生，无插件）：声明见 clipboard_image.cpp。
#ifndef RUNNER_CLIPBOARD_IMAGE_H_
#define RUNNER_CLIPBOARD_IMAGE_H_

#include <cstdint>
#include <vector>

namespace clipboard_image {

// Dart → 原生：把 RGBA 像素写入剪贴板（CF_DIB）。
bool CopyRgbaToClipboard(const std::vector<uint8_t>& rgba, int width, int height);

// 原生 → Dart：读取剪贴板的 CF_DIB 为 RGBA；不是图片则返回 false。
bool ReadClipboardRgba(std::vector<uint8_t>* out_rgba, int* out_width,
                       int* out_height);

}  // namespace clipboard_image

#endif  // RUNNER_CLIPBOARD_IMAGE_H_
