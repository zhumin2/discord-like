import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chord_client/image_compress.dart';

void main() {
  test('大 JPEG 压缩到 1600 长边，体积显著下降', () async {
    // 造一张有噪声的大图（避免纯色导致压缩比失真）
    final rnd = Random(42);
    final im = img.Image(width: 3000, height: 2000);
    for (var y = 0; y < im.height; y += 2) {
      for (var x = 0; x < im.width; x += 2) {
        im.setPixelRgb(x, y, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
      }
    }
    final jpg = Uint8List.fromList(img.encodeJpg(im, quality: 95));
    final out = await compressImageIfNeeded(jpg, 'photo.jpg');
    final decoded = img.decodeImage(out.bytes)!;
    print('原始 ${(jpg.length/1024).toStringAsFixed(0)}KB (3000x2000) → '
          '压缩 ${(out.bytes.length/1024).toStringAsFixed(0)}KB (${decoded.width}x${decoded.height}) name=${out.name}');
    expect(decoded.width, 1600);
    expect(out.bytes.length, lessThan(jpg.length ~/ 2));
    expect(out.name, 'photo.jpg');
  });

  test('小图不处理（保持原样）', () async {
    final im = img.Image(width: 200, height: 200);
    img.fill(im, color: img.ColorRgb8(120, 60, 200));
    final png = Uint8List.fromList(img.encodePng(im));
    final out = await compressImageIfNeeded(png, 'small.png');
    expect(out.bytes.length, png.length);
    expect(out.name, 'small.png');
  });

  test('非图片放行；PNG 透明图保留 alpha', () async {
    final txt = Uint8List.fromList(List.filled(300 * 1024, 65));
    final o1 = await compressImageIfNeeded(txt, 'a.pdf');
    expect(o1.bytes.length, txt.length);

    final im = img.Image(width: 2000, height: 1200, numChannels: 4);
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        im.setPixelRgba(x, y, 200, 100, 50, x < im.width ~/ 2 ? 0 : 255);
      }
    }
    final png = Uint8List.fromList(img.encodePng(im));
    final o2 = await compressImageIfNeeded(png, 'logo.png');
    expect(o2.name.endsWith('.png'), isTrue);
    final d = img.decodeImage(o2.bytes)!;
    expect(d.numChannels, 4);
    print('透明 PNG: ${(png.length/1024).toStringAsFixed(0)}KB → ${(o2.bytes.length/1024).toStringAsFixed(0)}KB');
  });

  test('头像参数：大图缩到 320 长边且 <100KB', () async {
    final rnd = Random(7);
    final im = img.Image(width: 2000, height: 1500);
    for (var y = 0; y < im.height; y += 2) {
      for (var x = 0; x < im.width; x += 2) {
        im.setPixelRgb(x, y, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
      }
    }
    final jpg = Uint8List.fromList(img.encodeJpg(im, quality: 95));
    final out = await compressImageIfNeeded(jpg, 'avatar.jpg',
        maxDim: 320, quality: 88, minBytes: 60 * 1024);
    final d = img.decodeImage(out.bytes)!;
    print('头像: ${(jpg.length/1024).toStringAsFixed(0)}KB (2000x1500) → '
        '${(out.bytes.length/1024).toStringAsFixed(1)}KB (${d.width}x${d.height})');
    expect(d.width, 320);
    expect(out.bytes.length, lessThan(100 * 1024));
  });
}
