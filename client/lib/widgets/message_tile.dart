import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'avatar.dart';
import 'rich_text.dart';

/// 单条消息：连续消息合并（compact）、悬浮操作条、表情回应徽章。
class MessageTile extends StatefulWidget {
  final Message msg;
  final bool compact; // 与上一条同作者且间隔 <5min
  final bool isMine;
  final void Function(String messageId, String emoji) onToggleReaction;
  final void Function(String messageId, String content) onEdit;
  final void Function(String messageId) onDelete;
  final void Function(Message msg)? onReply;       // 引用回复
  final void Function(String messageId)? onJumpToQuoted; // 点击引用块跳转
  final String Function(String url)? resolveUrl; // 相对 URL 解析（v1.1 图片）
  final bool highlighted; // 跳转定位时短暂高亮

  const MessageTile({
    super.key,
    required this.msg,
    required this.compact,
    required this.isMine,
    required this.onToggleReaction,
    required this.onEdit,
    required this.onDelete,
    this.onReply,
    this.onJumpToQuoted,
    this.resolveUrl,
    this.highlighted = false,
  });

  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool _hover = false;
  bool _editing = false;
  late TextEditingController _editCtl;

  static const pickerEmojis = [
    '👍', '❤️', '😂', '🎉', '👀', '🤔', '🚀', '🔥', '👏', '😅', '😭', '🤝', '✅', '❌', '🙏', '💯',
  ];

  @override
  void initState() {
    super.initState();
    _editCtl = TextEditingController(text: widget.msg.content);
  }

  @override
  void dispose() {
    _editCtl.dispose();
    super.dispose();
  }

  void _showReactionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ChordColors.bgDarker,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in pickerEmojis)
                _EmojiButton(
                  emoji: e,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onToggleReaction(widget.msg.id, e);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.msg;
    final timeStr = _timeLabel(m.createdAt);

    final content = _editing
        ? _buildEditor()
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RichTextSpan(
              m.content,
              baseStyle: const TextStyle(
                  fontSize: 15, height: 1.35, color: ChordColors.textNormal),
              resolveUrl: widget.resolveUrl,
            ),
          );

    // 引用块（被回复消息的摘要）
    final quote = m.replyTo == null
        ? null
        : _QuoteBlock(reply: m.replyTo!, onTap: widget.onJumpToQuoted);

    final body = widget.compact
        ? Padding(
            padding: const EdgeInsets.only(left: 68, right: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (quote != null) quote,
                content,
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(left: 16, right: 48, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(name: m.author?.username ?? '?',
                    colorHex: m.author?.avatarColor ?? '#5865F2',
                    imageUrl: m.author?.avatarUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              m.author?.username ?? '未知用户',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: widget.isMine
                                    ? ChordColors.textBright
                                    : _authorColor(m.authorId),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(timeStr,
                              style: const TextStyle(
                                  fontSize: 11, color: ChordColors.textMuted)),
                        ],
                      ),
                      if (quote != null) quote,
                      content,
                    ],
                  ),
                ),
              ],
            ),
          );

    final reactions = m.reactions;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            color: widget.highlighted
                ? const Color(0x33FFC857)
                : (_hover ? const Color(0x0DFFFFFF) : null),
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                body,
                if (reactions.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: widget.compact ? 68 : 68, top: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in reactions)
                          _ReactionChip(
                              summary: r,
                              onTap: () => widget.onToggleReaction(m.id, r.emoji)),
                        if (_hover) _AddReactionChip(onTap: _showReactionPicker),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 悬浮操作条
          if (_hover && !_editing)
            Positioned(
              right: 40,
              top: widget.compact ? -10 : -2,
              child: _ActionBar(
                isMine: widget.isMine,
                onReact: _showReactionPicker,
                onReply: widget.onReply == null ? null : () => widget.onReply!(widget.msg),
                onEdit: widget.isMine
                    ? () => setState(() {
                          _editCtl.text = widget.msg.content;
                          _editing = true;
                        })
                    : null,
                onDelete: widget.isMine ? _confirmDelete : null,
              ),
            ),
        ],
      ),
    );
  }

  Color _authorColor(String id) {
    const palette = [
      Color(0xFF9B59B6), Color(0xFF3498DB), Color(0xFF1ABC9C),
      Color(0xFFE67E22), Color(0xFFEB459E), Color(0xFF7289DA),
    ];
    return palette[id.hashCode.abs() % palette.length];
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final hm = '${_two(t.hour)}:${_two(t.minute)}';
    if (day == today) return '今天 $hm';
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hm';
    return '${t.year}/${t.month}/${t.day} $hm';
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _editCtl,
              autofocus: true,
              maxLines: null,
              style: const TextStyle(fontSize: 15, color: ChordColors.textNormal),
              decoration: const InputDecoration(
                hintText: '编辑消息，回车保存',
                isDense: true,
              ),
              onSubmitted: (v) {
                widget.onEdit(widget.msg.id, v);
                setState(() => _editing = false);
              },
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _editing = false),
            child: const Text('取消',
                style: TextStyle(color: ChordColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ChordColors.blurple,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
            ),
            onPressed: () {
              widget.onEdit(widget.msg.id, _editCtl.text);
              setState(() => _editing = false);
            },
            child: const Text('确定', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChordColors.bgDarker,
        title: const Text('删除消息'),
        content: const Text('删除后无法恢复，确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ChordColors.red),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete(widget.msg.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool isMine;
  final VoidCallback onReact;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ActionBar({
    required this.isMine,
    required this.onReact,
    this.onReply,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap, {Color? color}) {
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 17, color: color ?? ChordColors.textMuted),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: ChordColors.bgDarker,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x22FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.add_reaction_outlined, '添加回应', onReact),
          if (onReply != null) btn(Icons.reply, '引用回复', onReply),
          if (isMine) btn(Icons.edit_outlined, '编辑', onEdit),
          if (isMine) btn(Icons.delete_outline, '删除', onDelete, color: ChordColors.red),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final ReactionSummary summary;
  final VoidCallback onTap;
  const _ReactionChip({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = summary.mine;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? ChordColors.mentionBg : const Color(0xFF2B2D31),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? ChordColors.blurple : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(summary.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Text('${summary.count}',
                style: TextStyle(
                    fontSize: 12,
                    color: active ? ChordColors.mentionText : ChordColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _AddReactionChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddReactionChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2D31),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.add_reaction_outlined,
            size: 15, color: ChordColors.textMuted),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  const _EmojiButton({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: ChordColors.bgLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

/// 引用块：显示被回复消息的作者与摘要；点击跳转原消息。
/// 注意：消息列表外层是 SelectionArea，它的选择手势会赢走 InkWell 的 tap，
/// 所以这里用 Listener 在原始指针层判定「按下→抬起基本没移动」= 点击。
class _QuoteBlock extends StatefulWidget {
  final MessageReply reply;
  final void Function(String messageId)? onTap;

  const _QuoteBlock({required this.reply, this.onTap});

  @override
  State<_QuoteBlock> createState() => _QuoteBlockState();
}

class _QuoteBlockState extends State<_QuoteBlock> {
  Offset? _downPos;

  Color get _color {
    try {
      return Color(int.parse(widget.reply.authorColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      return ChordColors.blurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.reply;
    final snippet = reply.content.replaceAll('\n', ' ').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Listener(
        onPointerDown: (e) => _downPos = e.position,
        onPointerUp: (e) {
          final moved = _downPos == null ? 999.0 : (e.position - _downPos!).distance;
          _downPos = null;
          if (moved < 8 && widget.onTap != null) widget.onTap!(reply.id);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(4),
              border: Border(left: BorderSide(color: _color, width: 3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.reply, size: 12, color: ChordColors.textMuted),
                const SizedBox(width: 4),
                Text(reply.authorName,
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: _color)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    snippet.isEmpty ? '（无文字内容）' : snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: ChordColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
