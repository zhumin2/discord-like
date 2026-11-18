import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../cached_image.dart';

/// 圆形头像：优先显示 [imageUrl]（自定义图片，经服务器地址解析 + 磁盘缓存），
/// 否则显示首字母 + [colorHex] 颜色。[status] 非空时叠加在线状态点。
class Avatar extends ConsumerWidget {
  final String name;
  final String colorHex;
  final double size;
  final String? status; // online / idle / offline / null(不显示)
  final String? imageUrl; // 相对路径（/uploads/...）或完整 URL

  const Avatar({
    super.key,
    required this.name,
    required this.colorHex,
    this.size = 40,
    this.status,
    this.imageUrl,
  });

  Color get _color {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return ChordColors.blurple;
    }
  }

  static const _statusColors = {
    'online': ChordColors.green,
    'idle': ChordColors.yellow,
    'offline': Color(0xFF80848E),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(serverBaseProvider);
    final url = (imageUrl != null && imageUrl!.isNotEmpty)
        ? (imageUrl!.startsWith('http') ? imageUrl! : base + imageUrl!)
        : null;

    Widget inner;
    if (url != null) {
      inner = ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: CachedImage(url: url, fit: BoxFit.cover),
        ),
      );
    } else {
      final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
      inner = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (status == null) return inner;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          inner,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                color: _statusColors[status] ?? _statusColors['offline'],
                shape: BoxShape.circle,
                border: Border.all(
                  color: _statusColors[status] == ChordColors.green
                      ? ChordColors.green
                      : ChordColors.bgDark,
                  width: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
