import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'image_cache_dir.dart';

/// 带内存 + 磁盘两级缓存的图片组件（Web 上磁盘层交给浏览器 HTTP 缓存）。
///
/// 加载中显示 [placeholder]（默认 spinner 灰块），失败显示 [error]（默认断链图标）。
/// [maxWidth]/[maxHeight] 同时约束占位与图片。
class CachedImage extends StatefulWidget {
  final String url;
  final double? maxWidth;
  final double? maxHeight;
  final BoxFit fit;

  const CachedImage({
    super.key,
    required this.url,
    this.maxWidth,
    this.maxHeight,
    this.fit = BoxFit.contain,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = loadImageBytes(widget.url);
  }

  @override
  void didUpdateWidget(covariant CachedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _future = loadImageBytes(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _box(
            const Center(
                child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return _box(const Center(
              child: Icon(Icons.image_not_supported_outlined,
                  size: 30, color: Color(0xFF949BA4))));
        }
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.maxWidth ?? double.infinity,
            maxHeight: widget.maxHeight ?? double.infinity,
          ),
          child: Image.memory(bytes, fit: widget.fit, gaplessPlayback: true),
        );
      },
    );
  }

  Widget _box(Widget child) => Container(
        width: widget.maxWidth != null ? widget.maxWidth!.clamp(80, 320) : 320,
        height: widget.maxHeight != null ? widget.maxHeight!.clamp(60, 220) : 180,
        decoration: BoxDecoration(
          color: const Color(0xFF2B2D31),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(padding: const EdgeInsets.all(8), child: child),
      );
}

// ---------- 两级缓存 ----------

/// 内存层（应用生命周期内）；磁盘层见 image_cache_dir_*。
final Map<String, Uint8List> _memory = <String, Uint8List>{};
const int _memoryLimit = 80; // 张数上限（图片通常几百 KB，可控）

/// 下载/读缓存。返回 null 表示失败。
Future<Uint8List?> loadImageBytes(String url) async {
  final mem = _memory[url];
  if (mem != null) return mem;

  // 磁盘层（io 平台）
  try {
    final dir = await cacheDir();
    if (dir != null) {
      final key = sha1.convert(url.codeUnits).toString();
      final cached = await readCacheFile('$dir/$key');
      if (cached != null) {
        _remember(url, cached);
        return cached;
      }
    }
  } catch (_) {}

  // 网络
  try {
    final resp = await http.get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) return null;
    final bytes = resp.bodyBytes;

    _remember(url, bytes);
    try {
      final dir = await cacheDir();
      if (dir != null) {
        final key = sha1.convert(url.codeUnits).toString();
        await writeCacheFile('$dir/$key', bytes);
      }
    } catch (_) {}
    return bytes;
  } catch (_) {
    return null;
  }
}

void _remember(String url, Uint8List bytes) {
  if (_memory.length >= _memoryLimit) {
    _memory.remove(_memory.keys.first); // 简单 FIFO 淘汰
  }
  _memory[url] = bytes;
}

/// 清空图片缓存（调试/「清理空间」入口可用）。
Future<void> clearImageCache() async {
  _memory.clear();
  try {
    final dir = await cacheDir();
    if (dir != null) await deleteCacheDir(dir);
  } catch (_) {}
}
