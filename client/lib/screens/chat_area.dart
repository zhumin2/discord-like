import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../file_picker.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../image_compress.dart';
import '../widgets/composer.dart';
import '../widgets/dialogs.dart';
import '../widgets/message_tile.dart';

/// 聊天主区域：频道头部 + 消息列表 + typing 提示 + 输入框。
class ChatArea extends ConsumerStatefulWidget {
  final String channelId;
  final bool isDM;
  final VoidCallback? onOpenDrawer; // 手机端：☰ 打开抽屉
  final VoidCallback? onOpenMembers; // 手机端：👥 打开成员面板
  /// 是否渲染自带的顶部栏。窄屏由 HomeShell 提供统一的移动导航栏，这里传 false，
  /// 避免两条栏叠加、以及被系统状态栏覆盖（安卓机型上表现为"顶栏点不到"）。
  final bool showHeader;

  const ChatArea({
    super.key,
    required this.channelId,
    required this.isDM,
    this.onOpenDrawer,
    this.onOpenMembers,
    this.showHeader = true,
  });

  @override
  ConsumerState<ChatArea> createState() => _ChatAreaState();
}

class _ChatAreaState extends ConsumerState<ChatArea> {
  final _scrollCtl = ScrollController();
  Message? _replyTo; // 正在引用回复的消息（null=普通发送）
  String _selectedText = ''; // 当前选中的文本（跨消息选择，非空时显示「复制」按钮）
  final _jumpKey = GlobalKey(); // 跳转目标消息的定位锚点
  int _lastJumpTick = 0;

  @override
  void didUpdateWidget(covariant ChatArea old) {
    super.didUpdateWidget(old);
    // 切换频道/会话时清掉引用状态，避免回复到别的频道
    if (old.channelId != widget.channelId) _replyTo = null;
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  /// @ 自动补全候选来源：服务器 = 全体成员；DM = 对端 + 自己。
  List<String> _mentionNames(ChatState chat) {
    if (widget.isDM) {
      final dm = chat.dms.firstWhereOrNull((d) => d.id == widget.channelId);
      return [
        if (dm != null) dm.other.username,
        if (chat.me != null) chat.me!.username,
      ];
    }
    final gid = chat.guildId;
    if (gid == null) return const [];
    return (chat.members[gid] ?? const <MemberInfo>[])
        .map((m) => m.user.username)
        .toList();
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
    Channel? ch; // 当前频道对象（DM 时为 null）
    if (widget.isDM) {
      final dm = chat.dms.where((d) => d.id == widget.channelId).firstOrNull;
      title = dm?.other.username ?? '私信';
      subtitle = dm == null ? '' : (chat.presence[dm.other.id] == 'online' ? '在线' : '离线');
    } else {
      ch = chat.channels.values
          .expand((x) => x)
          .where((c) => c.id == widget.channelId)
          .firstOrNull;
      title = ch == null ? '' : '#${ch.name}';
      subtitle = ch?.category ?? '';
    }
    // 跳转定位：jumpTick 变化 → 下一帧滚动到目标消息并高亮 2.5s
    ref.listen(chatProvider.select((s) => s.jumpTick), (prev, next) {
      if (next != _lastJumpTick) {
        _lastJumpTick = next;
        WidgetsBinding.instance.addPostFrameCallback((_) => _revealJumpTarget());
      }
    });

    // 发言权限：DM 不限；频道按 speakMode 判定（服务器所有者恒可发言）
    final guild = chat.guilds.where((g) => g.id == chat.guildId).firstOrNull;
    final canSpeak =
        widget.isDM || (ch == null || ch.canSpeak(chat.me?.id ?? '', guild?.ownerId));

    return Column(
      children: [
        // 顶部栏（窄屏由 HomeShell 的 _MobileBar 替代）
        if (widget.showHeader) Container(
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
              if (!widget.isDM && chat.guildId != null)
                IconButton(
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: () => showSearchDialog(context, chat.guildId!),
                  tooltip: '搜索消息',
                ),
              if (widget.onOpenMembers != null)
                IconButton(
                  icon: const Icon(Icons.people_outline, size: 20),
                  onPressed: widget.onOpenMembers,
                  tooltip: '成员列表',
                ),
            ],
          ),
        ),
        // 消息列表（reverse + 向上分页）。
        // SelectionArea：支持跨多条消息选择文本（v 反馈 9）；
        // 自绘右键菜单修复「菜单鼠标一移动就消失无法点击」（v 反馈 5）。
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: SelectionArea(
            // 选区变化 → 显示固定「复制」按钮（鼠标移动不会消失，v 反馈 5/9）
            onSelectionChanged: (content) {
              final text = content?.plainText ?? '';
              if (text != _selectedText) {
                setState(() => _selectedText = text);
              }
            },
            contextMenuBuilder: (ctx, state) => _SelectionContextMenu(state: state),
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
                      // 跳转定位时放宽预构建范围，否则目标消息在视口外不会被 build，
                      // GlobalKey 拿不到 context，ensureVisible 无法滚动
                      cacheExtent: chat.highlightId != null ? 4000 : 250,
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
                          key: m.id == chat.highlightId ? _jumpKey : null,
                          msg: m,
                          compact: compact,
                          isMine: m.authorId == chat.me?.id,
                          highlighted: m.id == chat.highlightId,
                          onJumpToQuoted: (mid) => ref
                              .read(chatProvider.notifier)
                              .jumpToMessage(widget.channelId, mid),
                          onReply: (msg) => setState(() => _replyTo = msg),
                          onToggleReaction: (id, emoji) =>
                              ref.read(chatProvider.notifier).toggleReaction(id, emoji),
                          onEdit: (id, content) =>
                              ref.read(chatProvider.notifier).editMessage(id, content),
                          onDelete: (id) =>
                              ref.read(chatProvider.notifier).deleteMessage(id),
                          resolveUrl: (u) => u.startsWith('http')
                              ? u
                              : ref.read(serverBaseProvider) + u,
                        );
                      },
                    ),
                  ),
                ),
                ),
              ),
              if (_selectedText.trim().isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: Material(
                    color: Colors.transparent,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: ChordColors.bgModal,
                        foregroundColor: ChordColors.textBright,
                        side: const BorderSide(color: Color(0x33FFFFFF)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _selectedText));
                        if (!mounted) return;
                        setState(() => _selectedText = '');
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制选中内容')));
                      },
                      icon: const Icon(Icons.copy, size: 15),
                      label: Text('复制所选 ${_selectedText.trim().length} 字',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                ),
            ],
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
        if (!canSpeak) _LockedComposer(channelId: widget.channelId),
        if (canSpeak)
        Composer(
          channelName: title.replaceFirst('#', ''),
          isDM: widget.isDM,
          memberNames: _mentionNames(chat),
          replyAuthor: _replyTo?.author?.username,
          replySnippet: _replyTo?.content,
          replyColor: _replyTo == null ? null : _hexColor(_replyTo!.author?.avatarColor),
          onCancelReply: () => setState(() => _replyTo = null),
          onSend: (text) async {
            final replyId = _replyTo?.id;
            await ref.read(chatProvider.notifier).send(widget.channelId, text, replyToId: replyId);
            if (mounted) setState(() => _replyTo = null);
          },
          onTyping: () => ref.read(chatProvider.notifier).notifyTyping(widget.channelId),
          onAttach: () => _attachFile(),
          onPasteImage: _pasteImage,
        ),
      ],
    );
  }

  /// 滚动到跳转目标（等列表渲染后）并清除高亮。
  /// reverse 列表里第 i 条距离底部 (len-1-i) 条，先按平均高度估算 offset 粗跳，
  /// 再用 ensureVisible 精细对齐（目标项在 cacheExtent 内会被构建出来）。
  void _revealJumpTarget() {
    final chat = ref.read(chatProvider);
    final id = chat.highlightId;
    if (id != null) {
      final list = chat.messages[widget.channelId] ?? const <Message>[];
      final idx = list.indexWhere((m) => m.id == id);
      if (idx >= 0 && _scrollCtl.hasClients) {
        final fromEnd = list.length - 1 - idx;
        final est = (fromEnd * 62.0).clamp(0.0, _scrollCtl.position.maxScrollExtent);
        _scrollCtl.jumpTo(est);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _jumpKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: const Duration(milliseconds: 240));
      }
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) ref.read(chatProvider.notifier).clearHighlight();
    });
  }

  /// v1.1 附件：选文件 → （图片）压缩 → 上传 → 生成要插入输入框的 Markdown 文本。
  Future<String?> _attachFile() async {
    final picked = await pickFile(imagesOnly: false);
    if (picked == null) return null;
    return _uploadBytes(picked.bytes, picked.name, displayName: picked.name);
  }

  /// 剪贴板图片粘贴（v 反馈 1）：与附件同一条管线（压缩→上传→插入 Markdown）。
  Future<String?> _pasteImage(Uint8List bytes, String mime) async {
    final ext = mime.contains('png') ? 'png' : (mime.contains('webp') ? 'webp' : 'jpg');
    return _uploadBytes(bytes, 'clipboard.$ext');
  }

  Future<String?> _uploadBytes(Uint8List bytes, String name, {String? displayName}) async {
    final api = ref.read(apiProvider);
    if (api == null) return null;
    // 跨境带宽窄，图片先压缩再传（最长边 1600、JPEG q82；异常自动回退原图）
    final ready = await compressImageIfNeeded(bytes, name);
    final url = await api.upload(ready.bytes, ready.name);
    final ext = ready.name.toLowerCase().split('.').last;
    final isImage = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(ext);
    final label = displayName ?? ready.name;
    return isImage ? '\n![]($url)\n' : '[$label]($url)\n';
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

/// 把 "#RRGGBB" 解析成 Color（引用条左侧色条用）；非法值返回 null。
Color? _hexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return null;
  }
}

/// 受限频道（公告/静音）的输入区替代：提示 + 一键跳到第一个可发言的频道。
class _LockedComposer extends ConsumerWidget {
  final String channelId;
  const _LockedComposer({required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ChordColors.bgLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 15, color: ChordColors.textMuted),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('此频道仅特定成员可发言',
                style: TextStyle(fontSize: 13, color: ChordColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final chat = ref.read(chatProvider);
              final guild = chat.guilds
                  .where((g) => g.id == chat.guildId)
                  .firstOrNull;
              final list = chat.channels[guild?.id] ?? const <Channel>[];
              final target = list
                  .where((c) => c.id != channelId && c.canSpeak(chat.me?.id ?? '', guild?.ownerId))
                  .firstOrNull;
              if (target != null) {
                ref.read(chatProvider.notifier).selectChannel(target.id);
              }
            },
            child: const Text('去可发言的频道', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

/// 自绘文本选择右键菜单（复制 / 全选）。
/// 修复默认工具条在桌面 Web 上「鼠标一移动就消失、无法点击」的问题：
/// 用固定的 Material 卡片呈现，仅在选择变化或点击外部时收起。
class _SelectionContextMenu extends StatelessWidget {
  final SelectableRegionState state;
  const _SelectionContextMenu({required this.state});

  @override
  Widget build(BuildContext context) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ContextMenuButtonItem(
          onPressed: () => state.copySelection(SelectionChangedCause.toolbar),
          label: '复制',
        ),
        ContextMenuButtonItem(
          onPressed: () => state.selectAll(SelectionChangedCause.toolbar),
          label: '全选',
        ),
      ],
    );
  }
}
