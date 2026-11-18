import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models.dart';
import '../server_version.dart';
import '../widgets/avatar.dart';
import '../image_compress.dart';
import '../file_picker.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// 一次性弹窗集合：建服务器/邀请码/建频道/退服/删频道/搜用户发私信。

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
  );
}

Future<void> showAddGuildDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (ctx) => const _AddGuildDialog(),
  );
}

class _AddGuildDialog extends ConsumerStatefulWidget {
  const _AddGuildDialog();

  @override
  ConsumerState<_AddGuildDialog> createState() => _AddGuildDialogState();
}

class _AddGuildDialogState extends ConsumerState<_AddGuildDialog> {
  bool _create = false;
  final _nameCtl = TextEditingController();
  final _codeCtl = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _submitCreate() async {
    setState(() { _busy = true; _err = null; });
    await ref.read(chatProvider.notifier).createGuild(_nameCtl.text.trim());
    final err = ref.read(chatProvider).error;
    if (!mounted) return;
    if (err != null) {
      setState(() { _busy = false; _err = err; });
      ref.read(chatProvider.notifier).clearError();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submitJoin() async {
    setState(() { _busy = true; _err = null; });
    final err = await ref.read(chatProvider.notifier).joinByInvite(_codeCtl.text.trim());
    if (!mounted) return;
    if (err != null) {
      setState(() { _busy = false; _err = err; });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ChordColors.bgDarker,
      title: const Text('添加服务器'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('加入服务器'), icon: Icon(Icons.link)),
                ButtonSegment(value: true, label: Text('创建服务器'), icon: Icon(Icons.add)),
              ],
              selected: {_create},
              onSelectionChanged: (s) => setState(() => _create = s.first),
            ),
            const SizedBox(height: 16),
            if (_create) ...[
              TextField(
                controller: _nameCtl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '服务器名称，如：游戏开黑'),
              ),
              const SizedBox(height: 8),
              const Text('创建后会自动生成邀请码，可以分享给朋友',
                  style: TextStyle(fontSize: 12, color: ChordColors.textMuted)),
            ] else ...[
              TextField(
                controller: _codeCtl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '输入邀请码（演示服：demo2024）',
                ),
              ),
            ],
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!, style: const TextStyle(color: ChordColors.red, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : (_create ? _submitCreate : _submitJoin),
          child: Text(_busy ? '请稍候…' : (_create ? '创建' : '加入')),
        ),
      ],
    );
  }
}

Future<void> showInviteDialog(BuildContext context, Guild guild) async {
  final ref = ProviderScope.containerOf(context);
  final api = ref.read(apiProvider)!;
  final codeCtl = TextEditingController(text: guild.inviteCode);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ChordColors.bgDarker,
      title: Text('邀请好友加入 ${guild.name}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('把邀请码分享给朋友，对方在「添加服务器 → 加入服务器」中输入即可。',
                style: TextStyle(fontSize: 13, color: ChordColors.textMuted)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: codeCtl,
                    readOnly: true,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: ChordColors.textBright),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '复制邀请码',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: codeCtl.text));
                    if (context.mounted) _toast(context, '邀请码已复制');
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final code = await api.regenInvite(guild.id);
                  codeCtl.text = code;
                  ref.read(chatProvider.notifier).clearError();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重置邀请码'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}

Future<void> showCreateChannelDialog(BuildContext context, String guildId) async {
  final nameCtl = TextEditingController();
  final catCtl = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ChordColors.bgDarker,
      title: const Text('创建文字频道'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '频道名称，如：闲聊'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: catCtl,
              decoration: const InputDecoration(hintText: '分组（可选，如：综合）'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = nameCtl.text.trim();
            if (name.isEmpty) return;
            ProviderScope.containerOf(context)
                .read(chatProvider.notifier)
                .createChannel(guildId, name, catCtl.text.trim());
            Navigator.pop(ctx);
          },
          child: const Text('创建'),
        ),
      ],
    ),
  );
}

Future<void> showDeleteChannelDialog(BuildContext context, Channel channel) async {
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ChordColors.bgDarker,
      title: const Text('删除频道'),
      content: Text('确定删除 #${channel.name} 吗？其中的消息将一并删除。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ChordColors.red),
          onPressed: () {
            ProviderScope.containerOf(context)
                .read(chatProvider.notifier)
                .deleteChannel(channel.id);
            Navigator.pop(ctx);
          },
          child: const Text('删除'),
        ),
      ],
    ),
  );
}

Future<void> showLeaveGuildDialog(BuildContext context, Guild guild) async {
  final ref = ProviderScope.containerOf(context);
  final chat = ref.read(chatProvider);
  final isOwner = guild.ownerId == chat.me?.id;
  if (isOwner) {
    await showDialog(context: context, builder: (ctx) => _OwnerLeaveDialog(guild: guild));
  } else {
    await showDialog(context: context, builder: (ctx) => _MemberLeaveDialog(guild: guild));
  }
}

/// 成员退出：直接确认。
class _MemberLeaveDialog extends ConsumerWidget {
  final Guild guild;
  const _MemberLeaveDialog({required this.guild});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      backgroundColor: ChordColors.bgDarker,
      title: Text('退出 ${guild.name}'),
      content: const Text('退出后需要重新使用邀请码才能加入。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ChordColors.red),
          onPressed: () {
            ref.read(chatProvider.notifier).leaveGuild(guild.id);
            Navigator.pop(context);
          },
          child: const Text('退出'),
        ),
      ],
    );
  }
}

/// 所有者：转让所有权后退出，或解散服务器。
class _OwnerLeaveDialog extends ConsumerStatefulWidget {
  final Guild guild;
  const _OwnerLeaveDialog({required this.guild});

  @override
  ConsumerState<_OwnerLeaveDialog> createState() => _OwnerLeaveDialogState();
}

class _OwnerLeaveDialogState extends ConsumerState<_OwnerLeaveDialog> {
  String? _successorId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final others = (chat.members[widget.guild.id] ?? const <MemberInfo>[])
        .where((m) => m.user.id != chat.me?.id)
        .toList();
    return AlertDialog(
      backgroundColor: ChordColors.bgDarker,
      title: Text('退出 ${widget.guild.name}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('你是「${widget.guild.name}」的所有者。',
                style: const TextStyle(fontSize: 13.5)),
            const SizedBox(height: 12),
            if (others.isEmpty) ...[
              const Text('服务器里没有其他成员，只能解散服务器。',
                  style: TextStyle(fontSize: 13, color: ChordColors.textMuted)),
            ] else ...[
              const Text('退出前需要把所有权转让给一位成员：',
                  style: TextStyle(fontSize: 13.5)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _successorId,
                isExpanded: true,
                decoration: const InputDecoration(hintText: '选择新所有者'),
                items: [
                  for (final m in others)
                    DropdownMenuItem(
                        value: m.user.id, child: Text(m.user.username)),
                ],
                onChanged: (v) => setState(() => _successorId = v),
              ),
            ],
            const SizedBox(height: 10),
            const Text('也可以直接解散服务器，所有频道与消息将被删除。',
                style: TextStyle(fontSize: 12.5, color: ChordColors.textMuted)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: ChordColors.red),
          onPressed: _busy ? null : () async {
            final ok = await _confirm('解散服务器', '确定解散「${widget.guild.name}」吗？所有频道与消息将被永久删除。');
            if (!ok) return;
            setState(() => _busy = true);
            await ref.read(chatProvider.notifier).deleteGuild(widget.guild.id);
            if (mounted) Navigator.pop(context);
          },
          child: const Text('解散服务器'),
        ),
        if (others.isNotEmpty)
          FilledButton(
            onPressed: (_busy || _successorId == null) ? null : () async {
              setState(() => _busy = true);
              await ref
                  .read(chatProvider.notifier)
                  .leaveGuild(widget.guild.id, successorId: _successorId);
              if (mounted) Navigator.pop(context);
            },
            child: Text(_busy ? '请稍候…' : '转让并退出'),
          ),
      ],
    );
  }

  Future<bool> _confirm(String title, String content) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChordColors.bgDarker,
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ChordColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return res == true;
  }
}

/// 搜索用户并发起私信。
Future<void> showUserSearchDialog(BuildContext context) async {
  final ref = ProviderScope.containerOf(context);
  final api = ref.read(apiProvider)!;
  final qCtl = TextEditingController();
  List<Map<String, dynamic>> results = [];
  String? err;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: ChordColors.bgDarker,
        title: const Text('发起新私信'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qCtl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '输入用户名搜索'),
                onChanged: (v) async {
                  if (v.trim().isEmpty) {
                    setState(() => results = []);
                    return;
                  }
                  try {
                    final r = await api.searchUsers(v.trim());
                    setState(() { results = r; err = null; });
                  } on ApiException catch (e) {
                    setState(() => err = e.message);
                  }
                },
              ),
              const SizedBox(height: 10),
              ...results.map((u) {
                final user = User.fromJson(u);
                return ListTile(
                  leading: Avatar(name: user.username, colorHex: user.avatarColor, size: 34),
                  title: Text(user.username),
                  subtitle: Text(user.tag, style: const TextStyle(fontSize: 11)),
                  dense: true,
                  onTap: () async {
                    final dm = await ref.read(chatProvider.notifier).openDM(user.id);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (dm == null && context.mounted) {
                      _toast(context, ref.read(chatProvider).error ?? '发送失败');
                    }
                  },
                );
              }),
              if (err != null)
                Text(err!, style: const TextStyle(color: ChordColors.red, fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    ),
  );
}

/// 个人资料设置：改名 / 换头像颜色 / 上传头像图片。
Future<void> showProfileSettingsDialog(BuildContext context) async {
  await showDialog(context: context, builder: (ctx) => const _ProfileSettingsDialog());
}

class _ProfileSettingsDialog extends ConsumerStatefulWidget {
  const _ProfileSettingsDialog();

  @override
  ConsumerState<_ProfileSettingsDialog> createState() => _ProfileSettingsDialogState();
}

class _ProfileSettingsDialogState extends ConsumerState<_ProfileSettingsDialog> {
  late final TextEditingController _nameCtl =
      TextEditingController(text: ref.watch(chatProvider).me?.username ?? '');
  String _color = '';
  String? _avatarUrl; // 本地预览（上传后）；null = 未改动
  bool _busy = false;
  String? _err;

  static const palette = [
    '#5865F2', '#3BA55D', '#FAA61A', '#ED4245', '#EB459E',
    '#9B59B6', '#3498DB', '#1ABC9C', '#E67E22', '#7289DA',
  ];

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await pickFile(imagesOnly: true);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final ready = await compressImageIfNeeded(picked.bytes, picked.name);
      final url = await ref.read(apiProvider)!.upload(ready.bytes, ready.name);
      setState(() => _avatarUrl = url); // 仅预览，保存时 PATCH
    } catch (e) {
      setState(() => _err = '头像上传失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _err = '用户名不能为空');
      return;
    }
    setState(() { _busy = true; _err = null; });
    try {
      final me = ref.read(chatProvider).me!;
      final r = await ref.read(apiProvider)!.updateMe(
        username: name == me.username ? null : name,
        avatarColor: _color.isEmpty ? null : _color,
        avatarUrl: _avatarUrl, // null = 不改；'' = 清除自定义头像
      );
      ref.read(chatProvider.notifier).applyMe(r);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _err = '$e'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(chatProvider).me;
    final base = ref.watch(serverBaseProvider);
    final previewUrl = _avatarUrl ?? me?.avatarUrl ?? '';
    final previewColor = _color.isNotEmpty ? _color : (me?.avatarColor ?? '#5865F2');
    final avatarWidget = (previewUrl.isNotEmpty)
        ? ClipOval(
            child: Image.network(
              previewUrl.startsWith('http') ? previewUrl : base + previewUrl,
              width: 72, height: 72, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 72, height: 72, color: ChordColors.blurple,
                alignment: Alignment.center,
                child: Text(_nameCtl.text.isEmpty ? '?' : _nameCtl.text.characters.first,
                    style: const TextStyle(color: Colors.white, fontSize: 30)),
              ),
            ),
          )
        : Avatar(name: _nameCtl.text.isEmpty ? '?' : _nameCtl.text,
                 colorHex: previewColor, size: 72);

    return AlertDialog(
      backgroundColor: ChordColors.bgDarker,
      title: const Text('个人资料'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Stack(children: [
                avatarWidget,
                Positioned(
                  right: 0, bottom: 0,
                  child: InkWell(
                    onTap: _busy ? null : _pickAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: ChordColors.blurple,
                        shape: BoxShape.circle,
                        border: Border.all(color: ChordColors.bgDarker, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            const Text('用户名',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ChordColors.textMuted)),
            const SizedBox(height: 6),
            TextField(controller: _nameCtl),
            const SizedBox(height: 12),
            const Text('头像颜色',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ChordColors.textMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                for (final c in palette)
                  InkWell(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: Color(int.parse(c.replaceFirst('#', '0xFF'))),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                // 清除自定义头像（回到纯色）
                if (me?.avatarUrl != null && me!.avatarUrl.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _avatarUrl = ''),
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        border: Border.all(color: ChordColors.textMuted, width: 1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.no_photography, size: 13, color: ChordColors.textMuted),
                    ),
                  ),
              ],
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!, style: const TextStyle(color: ChordColors.red, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Divider(height: 1),
            const SizedBox(height: 8),
            VersionText(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}
