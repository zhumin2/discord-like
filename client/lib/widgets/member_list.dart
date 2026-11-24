import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'avatar.dart';

/// 右侧成员列表面板：在线/离开/离线分组。
class MemberList extends ConsumerWidget {
  final String guildId;
  const MemberList({super.key, required this.guildId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final members = chat.members[guildId] ?? const <MemberInfo>[];
    final mutedIn = _mutedChannelLabel(chat);

    // 以实时 presence 为准
    final online = members
        .where((m) => (chat.presence[m.user.id] ?? m.status) == 'online')
        .toList()
      ..sort((a, b) => a.user.username.compareTo(b.user.username));
    final idle = members
        .where((m) => (chat.presence[m.user.id] ?? m.status) == 'idle')
        .toList();
    final offline = members
        .where((m) {
          final s = chat.presence[m.user.id] ?? m.status;
          return s != 'online' && s != 'idle';
        })
        .toList()
      ..sort((a, b) => a.user.username.compareTo(b.user.username));

    Widget group(String label, List<MemberInfo> list, {bool dim = false}) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
            child: Text(
              '$label — ${list.length}',
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: ChordColors.textMuted),
            ),
          ),
          for (final m in list)
            Builder(builder: (ctx) => _MemberTile(
              member: m,
              status: chat.presence[m.user.id] ?? m.status,
              dim: dim,
              // 在当前频道不能发言的成员：头像上标一个禁言图标
              mutedTip: mutedIn(m),
              onTap: () => ref.read(chatProvider.notifier).openDM(m.user.id),
            )),
        ],
      );
    }

    return Container(
      color: ChordColors.bgDarker,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          group('在线', online),
          group('离开', idle),
          group('离线', offline, dim: true),
        ],
      ),
    );
  }
}

/// 返回一个判定函数：成员在「当前打开的频道」里是否不能发言；是则返回提示文案，否则 null。
/// 只对按人限制的模式（公告 / 指定成员）标记；「所有人」没人被禁言，
/// 「无人（归档）」是整个频道关闭，不逐个标记。
String? Function(MemberInfo) _mutedChannelLabel(ChatState chat) {
  final cid = chat.channelId;
  Channel? ch;
  if (cid != null) {
    for (final chs in chat.channels.values) {
      for (final c in chs) {
        if (c.id == cid) ch = c;
      }
    }
  }
  if (ch == null || (ch.speakMode != 'owner' && ch.speakMode != 'custom')) {
    return (_) => null;
  }
  final owner = chat.guilds.where((g) => g.id == ch!.guildId).firstOrNull?.ownerId;
  final channel = ch; // 提升到非空局部变量，闭包里才能直接用（mutable 局部变量不保留类型提升）
  return (m) {
    if (channel.canSpeak(m.user.id, owner)) return null;
    return channel.speakMode == 'owner'
        ? '在 #${channel.name} 不能发言（仅频道创建者可发言）'
        : '在 #${channel.name} 被禁言';
  };
}

class _MemberTile extends StatelessWidget {
  final MemberInfo member;
  final String status;
  final bool dim;
  final String? mutedTip; // 非空 = 在当前频道不能发言
  final VoidCallback onTap;

  const _MemberTile({
    required this.member,
    required this.status,
    required this.dim,
    required this.onTap,
    this.mutedTip,
  });

  @override
  Widget build(BuildContext context) {
    final u = member.user;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Opacity(
          opacity: dim ? 0.45 : 1,
          child: Row(
            children: [
              _AvatarWithMute(
                name: u.username,
                colorHex: u.avatarColor,
                imageUrl: u.avatarUrl,
                status: status,
                mutedTip: mutedTip,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.username,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                    Text(u.tag,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: ChordColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 头像 + 在线状态点；被禁言时在头像左下角叠一个 🔇 标记（与右下角的在线点对称）。
class _AvatarWithMute extends StatelessWidget {
  final String name;
  final String colorHex;
  final String? imageUrl;
  final String status;
  final String? mutedTip;

  const _AvatarWithMute({
    required this.name,
    required this.colorHex,
    required this.status,
    this.mutedTip,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Avatar(name: name, colorHex: colorHex, imageUrl: imageUrl, size: 32, status: status);
    if (mutedTip == null) return avatar;
    return Tooltip(
      message: mutedTip!,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              left: -4,
              bottom: -3,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2D31),
                  shape: BoxShape.circle,
                  border: Border.all(color: ChordColors.bgDarker, width: 2),
                ),
                child: const Icon(Icons.mic_off, size: 8, color: ChordColors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// DM 首页时的右侧栏：当前私信对象资料（简化版）。
class DMPartnerPanel extends ConsumerWidget {
  final String dmId;
  const DMPartnerPanel({super.key, required this.dmId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final dm = chat.dms.firstWhereOrNull((d) => d.id == dmId);
    if (dm == null) return const SizedBox.shrink();
    final status = chat.presence[dm.other.id] ?? 'offline';
    final statusLabel = {'online': '在线', 'idle': '离开', 'offline': '离线'}[status] ?? '';
    return Container(
      color: ChordColors.bgDarker,
      child: Column(
        children: [
          const SizedBox(height: 24),
          Avatar(name: dm.other.username, colorHex: dm.other.avatarColor, size: 72, status: status),
          const SizedBox(height: 12),
          Text(dm.other.username,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(dm.other.tag, style: const TextStyle(fontSize: 12, color: ChordColors.textMuted)),
          const SizedBox(height: 6),
          Text(statusLabel, style: const TextStyle(fontSize: 12, color: ChordColors.textMuted)),
        ],
      ),
    );
  }
}
