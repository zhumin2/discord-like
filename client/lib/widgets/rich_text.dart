import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../cached_image.dart';

import '../theme.dart';

/// 轻量 Markdown 风格富文本：**粗体** *斜体* `行内代码` ```代码块``` @提及 URL
/// 以及 v1.1 的图片 `![alt](url)`（支持相对 URL，经 resolveUrl 解析后内联渲染）。
class RichTextSpan extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final void Function(String url)? onLinkTap;

  /// 相对 URL → 完整 URL（如把 /uploads/... 拼上服务器地址）；null 则原样使用。
  final String Function(String url)? resolveUrl;

  const RichTextSpan(this.text,
      {super.key, this.baseStyle, this.onLinkTap, this.resolveUrl});

  String? _resolve(String url) {
    if (url.startsWith('http')) return url;
    final f = resolveUrl;
    return f != null ? f(url) : null;
  }

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(children: _parse(context)),
      style: baseStyle,
    );
  }

  // 图片语法：整体 URL 部分（含相对路径）
  static final RegExp _image = RegExp(r'!\[[^\]]*\]\((https?://[^\s)]+|/uploads/[^\s)]+)\)');

  List<InlineSpan> _parse(BuildContext context) {
    final spans = <InlineSpan>[];
    // 先按代码块切分
    final blocks = RegExp(r'```([\s\S]*?)```').allMatches(text);
    var cursor = 0;
    for (final b in blocks) {
      if (b.start > cursor) spans.addAll(_parseWithImages(text.substring(cursor, b.start), context));
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
    if (cursor < text.length) spans.addAll(_parseWithImages(text.substring(cursor), context));
    return spans;
  }

  /// 先把图片语法切出来渲染为图片组件，其余文本走普通行内解析。
  List<InlineSpan> _parseWithImages(String s, BuildContext context) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in _image.allMatches(s)) {
      if (m.start > cursor) spans.addAll(_parseInline(s.substring(cursor, m.start)));
      final url = _resolve(m.group(1)!);
      if (url != null) spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _imageWidget(url, context),
      ));
      cursor = m.end;
    }
    if (cursor < s.length) spans.addAll(_parseInline(s.substring(cursor)));
    return spans;
  }

  Widget _imageWidget(String url, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          barrierColor: Colors.black87,
          builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                maxScale: 5,
                child: CachedImage(url: url, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        child: CachedImage(
          url: url,
          maxWidth: 320,
          maxHeight: 220,
        ),
      ),
    );
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
