import 'package:flutter/material.dart';

import '../theme.dart';

/// 首字母圆形头像（用用户名与颜色哈希，无需图片上传）。
class Avatar extends StatelessWidget {
  final String name;
  final String colorHex;
  final double size;
  final String? status; // online / idle / offline / null(不显示)

  const Avatar({
    super.key,
    required this.name,
    required this.colorHex,
    this.size = 40,
    this.status,
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
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final avatar = Container(
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
    if (status == null) return avatar;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
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
