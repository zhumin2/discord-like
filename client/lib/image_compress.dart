import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 上传前图片压缩（纯 Dart，无平台插件）。
///
/// 背景：跨境带宽很窄（实测 10-50KB/s），800KB 的原图要传几十秒。
/// 处理策略：
///   - 仅处理 JPEG / PNG；GIF、WebP 等保持原样（可能含动画）
///   - 小于 [minBytes] 的小图直接放行，避免无谓的 CPU 开销
///   - 最长边超过 [maxDim] 时等比缩放（平均插值，缩图质量好）
///   - 有透明通道的 PNG 重新编码为 PNG（保留透明），其余转 JPEG（质量 [quality]）
///   - 任何异常 / 压缩后反而更大 ⇒ 回退原图，绝不阻断发送
Future<PickedBytes> compressImageIfNeeded(
  Uint8List bytes,
  String filename, {
  int maxDim = 1600,
  int quality = 82,
  int minBytes = 200 * 1024,
}) async {
  final ext = filename.toLowerCase().split('.').last;
  if (!const {'jpg', 'jpeg', 'png'}.contains(ext)) {
    return PickedBytes(bytes, filename);
  }
  if (bytes.length < minBytes) return PickedBytes(bytes, filename);

  try {
    // compute 在 IO 平台放到后台 isolate，避免压缩大图时界面卡顿（Web 上同步执行）
    final out = await compute(
        _compress, _CompressArgs(bytes, maxDim, quality, ext == 'png'));
    if (out == null || out.bytes.length >= bytes.length) {
      return PickedBytes(bytes, filename);
    }
    return PickedBytes(out.bytes, _rename(filename, out.isPng ? 'png' : 'jpg'));
  } catch (_) {
    return PickedBytes(bytes, filename); // 解码失败（伪造扩展名等）→ 原样上传
  }
}

class PickedBytes {
  final Uint8List bytes;
  final String name;
  const PickedBytes(this.bytes, this.name);
}

String _rename(String name, String ext) {
  final i = name.lastIndexOf('.');
  final base = i > 0 ? name.substring(0, i) : name;
  return '$base.$ext';
}

class _CompressArgs {
  final Uint8List bytes;
  final int maxDim;
  final int quality;
  final bool sourceIsPng;
  const _CompressArgs(this.bytes, this.maxDim, this.quality, this.sourceIsPng);
}

class _CompressResult {
  final Uint8List bytes;
  final bool isPng;
  const _CompressResult(this.bytes, this.isPng);
}

_CompressResult? _compress(_CompressArgs a) {
  final decoded = img.decodeImage(a.bytes);
  if (decoded == null) return null;

  var im = decoded;
  final w = im.width, h = im.height;
  final longest = w > h ? w : h;
  if (longest > a.maxDim) {
    final scale = a.maxDim / longest;
    im = img.copyResize(
      im,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  // PNG 带透明通道：保留 PNG 以免透明区域变黑；否则统一转 JPEG（体积小得多）
  if (a.sourceIsPng && im.numChannels == 4 && _hasAlpha(im)) {
    return _CompressResult(Uint8List.fromList(img.encodePng(im, level: 6)), true);
  }
  // 自适应质量：先按 82 编码，仍超过 targetBytes 就逐级降质量（最低 55）
  const targetBytes = 500 * 1024;
  var quality = a.quality;
  Uint8List out = Uint8List.fromList(img.encodeJpg(im, quality: quality));
  while (out.length > targetBytes && quality > 55) {
    quality -= 9;
    out = Uint8List.fromList(img.encodeJpg(im, quality: quality));
  }
  return _CompressResult(out, false);
}

bool _hasAlpha(img.Image im) {
  // 均匀采样最多 4096 个像素——大图上全量遍历开销不值当
  const maxSamples = 4096;
  final total = im.width * im.height;
  final step = (total / maxSamples).ceil().clamp(1, total);
  for (var i = 0; i < total; i += step) {
    final x = i % im.width, y = i ~/ im.width;
    if (im.getPixel(x, y).a < 250) return true;
  }
  return false;
}
