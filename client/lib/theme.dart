import 'package:flutter/material.dart';

/// Discord 风格暗色主题。
class ChordColors {
  static const blurple = Color(0xFF5865F2);
  static const green = Color(0xFF3BA55D);
  static const yellow = Color(0xFFFAA61A);
  static const red = Color(0xFFED4245);
  static const pink = Color(0xFFEB459E);

  // 背景（由深到浅）
  static const bgDarkest = Color(0xFF1E1F22); // 服务器 rail
  static const bgDarker = Color(0xFF2B2D31); // 频道列表/侧栏
  static const bgDark = Color(0xFF313338); // 聊天区
  static const bgLight = Color(0xFF383A40); // 输入框/hover
  static const bgModal = Color(0xFF4E5058);

  static const textNormal = Color(0xFFDBDEE1);
  static const textMuted = Color(0xFF949BA4);
  static const textBright = Color(0xFFF2F3F5);

  static const mentionBg = Color(0x3D5865F2);
  static const mentionText = Color(0xFFC9CDFB);
}

ThemeData buildChordTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'NotoSansSC', // 全局中文字体（内置 Noto Sans SC）
  );
  return base.copyWith(
    scaffoldBackgroundColor: ChordColors.bgDark,
    canvasColor: ChordColors.bgDarker,
    colorScheme: base.colorScheme.copyWith(
      primary: ChordColors.blurple,
      secondary: ChordColors.blurple,
      surface: ChordColors.bgDark,
      error: ChordColors.red,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: ChordColors.textNormal,
      displayColor: ChordColors.textBright,
    ),
    dividerColor: const Color(0x1F000000),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ChordColors.bgLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      hintStyle: const TextStyle(color: ChordColors.textMuted),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.all(Radius.circular(6))),
      textStyle: TextStyle(color: Colors.white, fontSize: 12),
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}
