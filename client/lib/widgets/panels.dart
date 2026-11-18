import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/dialogs.dart';

/// 最左侧服务器图标栏（含私信首页与添加按钮）。
class GuildRail extends ConsumerWidget {
  final VoidCallback onOpenDMs;

  const GuildRail({super.key, required this.onOpenDMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    return Container(
      width: 72,
      color: ChordColors.bgDarkest,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // 私信首页按钮（Discord logo 位置）
          _RailButton(
            selected: chat.guildId == null,
            label: '私信',
            color: ChordColors.blurple,
            badge: _dmBadge(chat),
            child: const Icon(Icons.forum_outlined, color: Colors.white, size: 26),
            onTap: onOpenDMs,
          ),
          const Divider(indent: 16, endIndent: 16, height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final g in chat.guilds)
                    _RailButton(
                      selected: chat.guildId == g.id,
                      label: g.name,
                      colorHex: g.iconColor,
                      badge: _guildBadge(chat, g.id),
                      onTap: () => ref.read(chatProvider.notifier).selectGuild(g.id),
                      child: Text(
                        g.name.isEmpty ? '?' : g.name.characters.first.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _RailButton(
            selected: false,
            label: '添加服务器',
            color: ChordColors.bgDark,
            child: const Icon(Icons.add, color: ChordColors.green, size: 24),
            onTap: () => showAddGuildDialog(context),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  int _guildBadge(ChatState chat, String guildId) {
    final chs = chat.channels[guildId] ?? const <Channel>[];
    var n = 0;
    for (final c in chs) {
      n += chat.summary[c.id]?.unread ?? 0;
    }
    return n;
  }

  /// 私信总未读（所有 DM 会话之和），显示在左上角消息图标上。
  int _dmBadge(ChatState chat) {
    var n = 0;
    for (final d in chat.dms) {
      n += chat.summary[d.id]?.unread ?? 0;
    }
    return n;
  }
}

class _RailButton extends StatelessWidget {
  final bool selected;
  final String label;
  final Widget child;
  final VoidCallback onTap;
  final String? colorHex;
  final Color color;
  final int badge;

  const _RailButton({
    required this.selected,
    required this.label,
    required this.child,
    required this.onTap,
    this.colorHex,
    this.color = ChordColors.bgDark,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 左侧选中指示条
            Positioned(
              left: -12,
              top: 4,
              bottom: 4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 4,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
            ),
            Center(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? (colorHex != null ? _hex(colorHex!) : color) : Colors.transparent,
                      borderRadius: BorderRadius.circular(selected ? 16 : 24),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                right: 4,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: ChordColors.red,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ChordColors.bgDarkest, width: 2),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _hex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return ChordColors.blurple;
    }
  }
}

/// 频道列表面板（服务器视图）。
class ChannelPanel extends ConsumerWidget {
  final String guildId;
  const ChannelPanel({super.key, required this.guildId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final guild = chat.guilds.where((g) => g.id == guildId).firstOrNull;
    final channels = chat.channels[guildId] ?? const <Channel>[];

    // 按 category 分组，保持顺序
    final categories = <String>[];
    for (final c in channels) {
      if (!categories.contains(c.category)) categories.add(c.category);
    }

    return Container(
      color: ChordColors.bgDarker,
      child: Column(
        children: [
          // 服务器名称头部
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x22000000))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    guild?.name ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15, color: ChordColors.textBright),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: ChordColors.textMuted),
                  color: ChordColors.bgModal,
                  onSelected: (v) {
                    if (v == 'invite') showInviteDialog(context, guild!);
                    if (v == 'create') showCreateChannelDialog(context, guildId);
                    if (v == 'leave') showLeaveGuildDialog(context, guild!);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'invite', child: Text('邀请码')),
                    PopupMenuItem(value: 'create', child: Text('创建频道')),
                    PopupMenuItem(value: 'leave', child: Text('退出服务器')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final cat in categories) ...[
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                            childrenPadding: EdgeInsets.zero,
                            iconColor: ChordColors.textMuted,
                            collapsedIconColor: ChordColors.textMuted,
                            title: Text(
                              cat.isEmpty ? '频道' : cat,
                              style: const TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w700,
                                  color: ChordColors.textMuted, letterSpacing: .3),
                            ),
                            children: [
                              for (final c in channels.where((x) => x.category == cat))
                                _ChannelTile(
                                  channel: c,
                                  selected: chat.channelId == c.id,
                                  summary: chat.summary[c.id],
                                  guildId: guildId,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // 底部当前用户栏
          _UserBar(),
        ],
      ),
    );
  }
}

class _ChannelTile extends ConsumerWidget {
  final Channel channel;
  final bool selected;
  final ChannelSummary? summary;
  final String guildId;

  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.summary,
    required this.guildId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = summary?.unread ?? 0;
    final mentions = summary?.mentions ?? 0;
    final chat = ref.watch(chatProvider);
    final isOwner = chat.guilds.where((g) => g.id == guildId).firstOrNull?.ownerId == chat.me?.id;

    return InkWell(
      onTap: () => ref.read(chatProvider.notifier).selectChannel(channel.id),
      onLongPress: isOwner
          ? () => showDeleteChannelDialog(context, channel)
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0x33FFFFFF) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(Icons.tag, size: 18, color: ChordColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                channel.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? ChordColors.textBright : ChordColors.textMuted,
                ),
              ),
            ),
            if (isOwner && !selected)
              InkWell(
                onTap: () => showDeleteChannelDialog(context, channel),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 14, color: ChordColors.textMuted),
                ),
              ),
            if (mentions > 0)
              _CountBadge(count: mentions, mention: true)
            else if (unread > 0 && !selected)
              _CountBadge(count: unread, mention: false),
          ],
        ),
      ),
    );
  }
}

class _UserBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final me = chat.me;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: ChordColors.bgDarkest,
      child: Row(
        children: [
          // 点击自己的头像/名字打开个人资料设置
          Expanded(
            child: InkWell(
              onTap: () => showProfileSettingsDialog(context),
              child: Row(
                children: [
          Avatar(
            name: me?.username ?? '?',
            colorHex: me?.avatarColor ?? '#5865F2',
            imageUrl: me?.avatarUrl,
            size: 32,
            status: 'online',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me?.username ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(me?.tag ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: ChordColors.textMuted)),
              ],
            ),
          ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout, size: 18, color: ChordColors.textMuted),
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: ChordColors.bgDarker,
                title: const Text('退出登录'),
                content: const Text('确定要退出当前账号吗？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(tokenProvider.notifier).set(null);
                    },
                    child: const Text('退出'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 私信列表面板（DM 首页视图的第二栏）。
class DMPanel extends ConsumerWidget {
  const DMPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    return Container(
      color: ChordColors.bgDarker,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x22000000))),
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Expanded(
                  child: Text('私信',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                IconButton(
                  tooltip: '发起新私信',
                  icon: const Icon(Icons.edit_outlined, size: 17, color: ChordColors.textMuted),
                  onPressed: () => showUserSearchDialog(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: chat.dms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.waving_hand_outlined, size: 40, color: ChordColors.textMuted),
                        const SizedBox(height: 10),
                        const Text('还没有私信',
                            style: TextStyle(color: ChordColors.textMuted)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => showUserSearchDialog(context),
                          icon: const Icon(Icons.search),
                          label: const Text('搜索用户'),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    children: [
                      for (final dm in chat.dms)
                        _DMTile(
                          dm: dm,
                          selected: chat.channelId == dm.id && chat.guildId == null,
                          unread: chat.summary[dm.id]?.unread ?? 0,
                        ),
                    ],
                  ),
          ),
          _UserBar(),
        ],
      ),
    );
  }
}

class _DMTile extends ConsumerWidget {
  final DMSession dm;
  final bool selected;
  final int unread;

  const _DMTile({required this.dm, required this.selected, required this.unread});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => ref.read(chatProvider.notifier).selectChannel(dm.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0x33FFFFFF) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Avatar(
              name: dm.other.username,
              colorHex: dm.other.avatarColor,
              imageUrl: dm.other.avatarUrl,
              size: 34,
              status: chat.presence[dm.other.id] ?? 'offline',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                dm.other.username,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? ChordColors.textBright : ChordColors.textNormal,
                ),
              ),
            ),
            if (unread > 0) _CountBadge(count: unread, mention: false),
          ],
        ),
      ),
    );
  }
}

/// 未读/提及数字徽章。
/// - 普通未读：深红底、常规字重（1-99，超过显示 99+）
/// - @提及：亮红底 + 白色描边 + 轻微发光 + 粗体，视觉上更强
class _CountBadge extends StatelessWidget {
  final int count;
  final bool mention;

  const _CountBadge({required this.count, required this.mention});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    final color = mention ? const Color(0xFFFF2D3F) : const Color(0xFFDA373C);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: mention ? Border.all(color: const Color(0x73FFFFFF), width: 0.5) : null,
        boxShadow: mention
            ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 6, spreadRadius: 1)]
            : null,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.3,
          color: Colors.white,
          fontWeight: mention ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}
