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
            _MemberTile(
              member: m,
              status: chat.presence[m.user.id] ?? m.status,
              dim: dim,
              onTap: () => ref.read(chatProvider.notifier).openDM(m.user.id),
            ),
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

class _MemberTile extends StatelessWidget {
  final MemberInfo member;
  final String status;
  final bool dim;
  final VoidCallback onTap;

  const _MemberTile({
    required this.member,
    required this.status,
    required this.dim,
    required this.onTap,
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
              Avatar(name: u.username, colorHex: u.avatarColor, imageUrl: u.avatarUrl, size: 32, status: status),
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
