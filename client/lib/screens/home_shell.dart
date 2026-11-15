import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme.dart';
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
      );
    }

    if (isWide) {
      final membersPanel = showDMView
          ? (chat.channelId != null
              ? DMPartnerPanel(dmId: chat.channelId!)
              : const SizedBox())
          : MemberList(guildId: chat.guildId!);
      // Material 祖先必须有：否则 Text 会以红字+黄下划线的调试样式渲染
      return Material(
        color: ChordColors.bgDark,
        child: Row(
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
          child: Row(children: [
            SizedBox(width: 72, child: rail),
            Expanded(child: panel),
          ]),
        ),
      ),
      body: Builder(
        builder: (ctx) => Stack(
          children: [
            chatArea,
            // 窄屏没有 menu 按钮时 ChatArea 顶部自带按钮；这里兜底 DM 首页无频道选中时也提供入口
            if (chat.channelId == null)
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
          ],
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

