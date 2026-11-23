import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/member_list.dart';
import '../widgets/panels.dart';
import 'chat_area.dart';

/// 响应式主外壳：
/// - 宽屏(≥1000px)：服务器 rail | 频道/私信栏 | 聊天区 | 成员栏
/// - 窄屏(<1000px)：聊天区 + 侧滑抽屉（rail+频道栏），顶栏按钮切换成员 BottomSheet
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const wideBreakpoint = 1000.0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openMembersSheet() {
    final chat = ref.read(chatProvider);
    final guildId = chat.guildId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChordColors.bgDarker,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ChordColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('成员列表',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Expanded(
              child: guildId == null
                  ? const Center(child: Text('服务器成员列表在服务器视图中查看',
                      style: TextStyle(color: ChordColors.textMuted)))
                  : MemberList(guildId: guildId),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 别人在其它频道 @ 我：弹一条提示（mentionTick 每次提及 +1）
    ref.listen(chatProvider.select((s) => s.mentionTick), (prev, next) {
      if (next > (prev ?? 0)) {
        final text = ref.read(chatProvider).mentionText;
        if (text != null && text.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(
              children: [
                const Icon(Icons.alternate_email, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
              ],
            ),
            duration: const Duration(seconds: 4),
          ));
        }
      }
    });
    final chat = ref.watch(chatProvider);
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= wideBreakpoint;
    final showDMView = chat.guildId == null;
    final isDMChannel = chat.channelId != null &&
        chat.dms.any((d) => d.id == chat.channelId);

    final rail = GuildRail(onOpenDMs: () {
      ref.read(chatProvider.notifier).selectDMHome();
      if (!isWide) Navigator.pop(context); // 手机端抽屉打开时点击后关闭
    });

    final panel = showDMView
        ? (const DMPanel() as Widget)
        : ChannelPanel(guildId: chat.guildId!);

    // 聊天区
    Widget chatArea;
    if (chat.channelId == null) {
      chatArea = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(showDMView ? Icons.chat_bubble_outline : Icons.tag,
                size: 56, color: const Color(0x55FFFFFF)),
            const SizedBox(height: 12),
            Text(
              showDMView ? '选择一个私信会话' : '选择左侧频道开始聊天',
              style: const TextStyle(color: ChordColors.textMuted),
            ),
          ],
        ),
      );
    } else {
      chatArea = ChatArea(
        channelId: chat.channelId!,
        isDM: isDMChannel,
        onOpenDrawer: isWide ? null : () => _scaffoldKey.currentState?.openDrawer(),
        onOpenMembers: isWide ? null : _openMembersSheet,
        // 窄屏：不使用 ChatArea 自带顶栏，改用下方的统一移动导航栏
        showHeader: isWide,
      );
    }

    if (isWide) {
      final membersPanel = showDMView
          ? (chat.channelId != null
              ? DMPartnerPanel(dmId: chat.channelId!)
              : const SizedBox())
          : MemberList(guildId: chat.guildId!);
      // 用 Scaffold（而不是裸 Material）：既提供 Material 祖先（否则 Text 是红字黄下划线
      // 调试样式），也让 ScaffoldMessenger 有宿主——宽屏下 @ 提及的 SnackBar 才能显示。
      return Scaffold(
        backgroundColor: ChordColors.bgDark,
        body: Row(
          children: [
            rail,
            SizedBox(width: 240, child: panel),
            Expanded(child: chatArea),
            if (chat.channelId != null)
              Container(width: 240, color: ChordColors.bgDarker, child: membersPanel),
          ],
        ),
      );
    }

    // 窄屏：抽屉 = rail + panel
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: ChordColors.bgDark,
      drawer: Theme(
        data: Theme.of(context).copyWith(canvasColor: ChordColors.bgDarker),
        child: Drawer(
          width: 300,
          backgroundColor: ChordColors.bgDarker,
          child: SafeArea(
            right: false,
            bottom: false,
            child: Row(children: [
              SizedBox(width: 72, child: rail),
              Expanded(child: panel),
            ]),
          ),
        ),
      ),
      body: Builder(
        builder: (ctx) => SafeArea(
          // 顶部让出状态栏、底部留给输入框自己处理（Composer 已加 padding.bottom）
          bottom: false,
          child: Column(
            children: [
              _MobileBar(
                title: _mobileTitle(chat),
                subtitle: _mobileSubtitle(chat),
                isDM: isDMChannel,
                onOpenDrawer: () => Scaffold.of(ctx).openDrawer(),
                onOpenMembers: chat.guildId != null && !isDMChannel
                    ? _openMembersSheet
                    : null,
                onSearch: chat.guildId != null && !isDMChannel
                    ? () => showSearchDialog(context, chat.guildId!)
                    : null,
              ),
              Expanded(child: chatArea),
            ],
          ),
        ),
      ),
    );
  }
}

/// 成员列表用于 BottomSheet。
class MemberListInner extends StatelessWidget {
  final String guildId;
  const MemberListInner({super.key, required this.guildId});

  @override
  Widget build(BuildContext context) {
    return MemberList(guildId: guildId);
  }
}

/// 窄屏导航栏标题：私信显示对方用户名，频道显示 #名称，未选中显示 Chord。
String _mobileTitle(ChatState chat) {
  final cid = chat.channelId;
  if (cid == null) return 'Chord';
  final dm = chat.dms.where((d) => d.id == cid).firstOrNull;
  if (dm != null) return dm.other.username;
  final ch = chat.channels.values
      .expand((x) => x)
      .where((c) => c.id == cid)
      .firstOrNull;
  return ch == null ? 'Chord' : ch.name;
}

String _mobileSubtitle(ChatState chat) {
  final cid = chat.channelId;
  if (cid == null) return '';
  if (chat.dms.any((d) => d.id == cid)) return '私信';
  final ch = chat.channels.values
      .expand((x) => x)
      .where((c) => c.id == cid)
      .firstOrNull;
  return ch?.category ?? '';
}

/// 窄屏统一导航栏（替代 ChatArea 自带顶栏）：
/// [☰ 频道/服务器] 标题（#频道 / 私信对象） [👥 成员]
/// 放在 SafeArea 内，安卓状态栏不会盖住；始终存在，未选频道时也能打开抽屉。
class _MobileBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isDM;
  final VoidCallback onOpenDrawer;
  final VoidCallback? onOpenMembers;
  final VoidCallback? onSearch;

  const _MobileBar({
    required this.title,
    required this.subtitle,
    required this.isDM,
    required this.onOpenDrawer,
    this.onOpenMembers,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: ChordColors.bgDark,
        border: Border(bottom: BorderSide(color: Color(0x22000000))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, size: 22),
            tooltip: '频道与服务器',
            onPressed: onOpenDrawer,
          ),
          Icon(isDM ? Icons.alternate_email : Icons.tag,
              size: 19, color: ChordColors.textMuted),
          const SizedBox(width: 5),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: ChordColors.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onSearch != null)
            IconButton(
              icon: const Icon(Icons.search, size: 20),
              tooltip: '搜索消息',
              onPressed: onSearch,
            ),
          if (onOpenMembers != null)
            IconButton(
              icon: const Icon(Icons.people_outline, size: 21),
              tooltip: '成员列表',
              onPressed: onOpenMembers,
            ),
        ],
      ),
    );
  }
}
