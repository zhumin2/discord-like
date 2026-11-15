import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/composer.dart';
import '../widgets/message_tile.dart';

/// 聊天主区域：频道头部 + 消息列表 + typing 提示 + 输入框。
class ChatArea extends ConsumerStatefulWidget {
  final String channelId;
  final bool isDM;
  final VoidCallback? onOpenDrawer; // 手机端：☰ 打开抽屉
  final VoidCallback? onOpenMembers; // 手机端：👥 打开成员面板

  const ChatArea({
    super.key,
    required this.channelId,
    required this.isDM,
    this.onOpenDrawer,
    this.onOpenMembers,
  });

  @override
  ConsumerState<ChatArea> createState() => _ChatAreaState();
}

class _ChatAreaState extends ConsumerState<ChatArea> {
  final _scrollCtl = ScrollController();

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final messages = chat.messages[widget.channelId] ?? const <Message>[];
    final noMore = chat.noMore.contains(widget.channelId);
    final typing = chat.typing[widget.channelId] ?? const <String>[];

    // 频道名与说明
    String title;
    String subtitle;
    if (widget.isDM) {
      final dm = chat.dms.where((d) => d.id == widget.channelId).firstOrNull;
      title = dm?.other.username ?? '私信';
      subtitle = dm == null ? '' : (chat.presence[dm.other.id] == 'online' ? '在线' : '离线');
    } else {
      final ch = chat.channels.values
          .expand((x) => x)
          .where((c) => c.id == widget.channelId)
          .firstOrNull;
      title = ch == null ? '' : '#${ch.name}';
      subtitle = ch?.category ?? '';
    }

    return Column(
      children: [
        // 顶部栏
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: ChordColors.bgDark,
            border: Border(bottom: BorderSide(color: Color(0x22000000))),
          ),
          child: Row(
            children: [
              if (widget.onOpenDrawer != null)
                IconButton(
                  icon: const Icon(Icons.menu, size: 20),
                  onPressed: widget.onOpenDrawer,
                  tooltip: '频道列表',
                ),
              Icon(widget.isDM ? Icons.alternate_email : Icons.tag,
                  size: 20, color: ChordColors.textMuted),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(width: 1, height: 18, color: const Color(0x33FFFFFF)),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: ChordColors.textMuted)),
                ),
              ],
              const Spacer(),
              if (widget.onOpenMembers != null)
                IconButton(
                  icon: const Icon(Icons.people_outline, size: 20),
                  onPressed: widget.onOpenMembers,
                  tooltip: '成员列表',
                ),
            ],
          ),
        ),
        // 消息列表（reverse + 向上分页）
        Expanded(
          child: messages.isEmpty
              ? _EmptyState(isDM: widget.isDM, title: title)
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    // reverse 列表滚到底部（视觉上的顶部）= 加载更早消息
                    if (n is ScrollEndNotification &&
                        n.metrics.extentAfter < 60 &&
                        !noMore) {
                      ref.read(chatProvider.notifier).loadOlder(widget.channelId);
                    }
                    return false;
                  },
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ListView.builder(
                      controller: _scrollCtl,
                      reverse: true,
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      itemCount: messages.length + (noMore ? 0 : 1),
                      itemBuilder: (context, i) {
                        // reverse 列表：i=0 是最新一条
                        final idx = messages.length - 1 - i;
                        if (idx < 0) {
                          return const Padding(
                            padding: EdgeInsets.all(14),
                            child: Center(
                                child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )),
                          );
                        }
                        final m = messages[idx];
                        final prev = idx > 0 ? messages[idx - 1] : null;
                        final compact = prev != null &&
                            prev.authorId == m.authorId &&
                            m.createdAt.difference(prev.createdAt).inMinutes.abs() < 5;
                        return MessageTile(
                          msg: m,
                          compact: compact,
                          isMine: m.authorId == chat.me?.id,
                          onToggleReaction: (id, emoji) =>
                              ref.read(chatProvider.notifier).toggleReaction(id, emoji),
                          onEdit: (id, content) =>
                              ref.read(chatProvider.notifier).editMessage(id, content),
                          onDelete: (id) =>
                              ref.read(chatProvider.notifier).deleteMessage(id),
                        );
                      },
                    ),
                  ),
                ),
        ),
        // typing 提示
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: typing.isEmpty
              ? const SizedBox(height: 18)
              : SizedBox(
                  height: 18,
                  key: ValueKey(typing.join(',')),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${typing.join('、')} 正在输入',
                            style: const TextStyle(
                                fontSize: 11.5, color: ChordColors.textMuted)),
                        const WidgetSpan(
                          child: _TypingDots(),
                        ),
                      ]),
                    ),
                  ),
                ),
        ),
        Composer(
          channelName: title.replaceFirst('#', ''),
          isDM: widget.isDM,
          onSend: (text) => ref.read(chatProvider.notifier).send(widget.channelId, text),
          onTyping: () => ref.read(chatProvider.notifier).notifyTyping(widget.channelId),
        ),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        final n = (_ctl.value * 3).floor() % 3 + 1;
        return Text('.' * n,
            style: const TextStyle(fontSize: 11.5, color: ChordColors.textMuted));
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDM;
  final String title;
  const _EmptyState({required this.isDM, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDM ? Icons.alternate_email : Icons.tag,
            size: 64,
            color: const Color(0x88FFFFFF),
          ),
          const SizedBox(height: 12),
          Text('欢迎来到 $title',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                  color: ChordColors.textBright)),
          const SizedBox(height: 6),
          const Text('这里是频道的开始，发一条消息打个招呼吧！',
              style: TextStyle(color: ChordColors.textMuted)),
        ],
      ),
    );
  }
}
