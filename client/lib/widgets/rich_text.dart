import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// 轻量 Markdown 风格富文本：**粗体** *斜体* `行内代码` ```代码块``` @提及 URL。
class RichTextSpan extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final void Function(String url)? onLinkTap;

  const RichTextSpan(this.text, {super.key, this.baseStyle, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(children: _parse(context)),
      style: baseStyle,
    );
  }

  List<InlineSpan> _parse(BuildContext context) {
    final spans = <InlineSpan>[];
    // 先按代码块切分
    final blocks = RegExp(r'```([\s\S]*?)```').allMatches(text);
    var cursor = 0;
    for (final b in blocks) {
      if (b.start > cursor) spans.addAll(_parseInline(text.substring(cursor, b.start)));
      final code = b.group(1) ?? '';
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: const BoxDecoration(
            color: Color(0xFF2B2D31),
            borderRadius: BorderRadius.all(Radius.circular(5)),
            border: Border(left: BorderSide(color: Color(0xFF4E5058), width: 3)),
          ),
          child: SelectableText(
            code.startsWith('\n') ? code.substring(1) : code,
            style: const TextStyle(
              fontFamily: 'Consolas, monospace', fontSize: 13,
              color: ChordColors.textNormal,
            ),
          ),
        ),
      ));
      cursor = b.end;
    }
    if (cursor < text.length) spans.addAll(_parseInline(text.substring(cursor)));
    return spans;
  }

  List<InlineSpan> _parseInline(String s) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\*\*(.+?)\*\*)'      // 1,2 粗体
      '|(\\*(.+?)\\*)'        // 3,4 斜体
      '|(`([^`]+)`)'          // 5,6 行内代码
      '|(@[\w\u4e00-\u9fa5-]+(?:#\d{4})?)' // @提及
      '|(https?://[^\s<>]+)', // URL
      unicode: true,
    );
    var cursor = 0;
    for (final m in pattern.allMatches(s)) {
      if (m.start > cursor) spans.add(TextSpan(text: s.substring(cursor, m.start)));
      final base = baseStyle ?? const TextStyle();
      if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(fontStyle: FontStyle.italic)));
      } else if (m.group(6) != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2D31),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(m.group(6)!,
                style: base.copyWith(fontFamily: 'Consolas, monospace', fontSize: 13)),
          ),
        ));
      } else if (m.group(0).toString().startsWith('@')) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
            decoration: BoxDecoration(
              color: ChordColors.mentionBg,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(m.group(0)!,
                style: base.copyWith(
                    color: ChordColors.mentionText,
                    backgroundColor: Colors.transparent,
                    fontWeight: FontWeight.w500)),
          ),
        ));
      } else if (m.group(0).toString().startsWith('http')) {
        final url = m.group(0)!;
        spans.add(TextSpan(
          text: url,
          style: base.copyWith(color: const Color(0xFF00A8FC), decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () => onLinkTap?.call(url),
        ));
      }
      cursor = m.end;
    }
    if (cursor < s.length) spans.add(TextSpan(text: s.substring(cursor)));
    return spans;
  }
}
