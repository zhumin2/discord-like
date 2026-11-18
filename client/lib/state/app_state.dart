import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../gateway.dart';
import '../models.dart';
import '../storage.dart';

/// 服务器地址（REST/WS 共用），持久化。手机真机调试时改为电脑局域网 IP。
class ServerBaseNotifier extends Notifier<String> {
  @override
  String build() => _initial;
  static String _initial = _defaultBase();

  /// Web 端默认从页面地址推导 API（部署到任意主机开箱即用）；
  /// 桌面/移动端可用 --dart-define=CHORD_DEFAULT_BASE=... 指定默认服务器；
  /// 本机调试保持 127.0.0.1。
  static String _defaultBase() {
    const fromDefine = String.fromEnvironment('CHORD_DEFAULT_BASE');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kIsWeb) {
      final u = Uri.base;
      if (u.host.isNotEmpty && u.host != 'localhost' && u.host != '127.0.0.1') {
        return '${u.scheme}://${u.host}:8081';
      }
    }
    return 'http://127.0.0.1:8081';
  }

  static Future<void> restore() async {
    _initial = await KeyValueStore.getString('serverBase') ?? _initial;
  }

  Future<void> set(String v) async {
    v = v.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!v.startsWith('http')) v = 'http://$v';
    state = v;
    await KeyValueStore.setString('serverBase', v);
  }
}

final serverBaseProvider =
    NotifierProvider<ServerBaseNotifier, String>(ServerBaseNotifier.new);

/// 登录 token，持久化。
class TokenNotifier extends Notifier<String?> {
  @override
  String? build() => _initial;
  static String? _initial;

  static Future<void> restore() async {
    _initial = await KeyValueStore.getString('token');
  }

  Future<void> set(String? v) async {
    state = v;
    await KeyValueStore.setString('token', v);
  }
}

final tokenProvider = NotifierProvider<TokenNotifier, String?>(TokenNotifier.new);

/// REST 客户端，随 base/token 重建。
final apiProvider = Provider<ApiClient?>((ref) {
  final token = ref.watch(tokenProvider);
  final base = ref.watch(serverBaseProvider);
  if (token == null) return null;
  return ApiClient(base: base, token: token);
});

/// WebSocket 网关，随 base/token 重建。
final gatewayProvider = Provider<Gateway?>((ref) {
  final token = ref.watch(tokenProvider);
  final base = ref.watch(serverBaseProvider);
  if (token == null) return null;
  final gw = Gateway(base: base, token: token);
  gw.connect();
  ref.onDispose(gw.dispose);
  return gw;
});

/// 聊天总状态。
class ChatState {
  final User? me;
  final bool loading; // bootstrap 中
  final String? error; // 全局错误提示（toast 用后清除）
  final List<Guild> guilds;
  final Map<String, List<Channel>> channels; // guildId -> list
  final List<DMSession> dms;
  final Map<String, List<Message>> messages; // channelId -> 正序列表
  final Set<String> noMore; // channelId：已无更早消息
  final Map<String, ChannelSummary> summary; // channelId -> 未读
  final Map<String, String> presence; // userId -> online/idle/offline
  final Map<String, List<String>> typing; // channelId -> 正在输入的用户名
  final String? guildId; // 当前服务器（null = 私信首页视图）
  final String? channelId; // 当前频道或私信会话
  final Map<String, List<MemberInfo>> members; // guildId -> 成员

  const ChatState({
    this.me,
    this.loading = false,
    this.error,
    this.guilds = const [],
    this.channels = const {},
    this.dms = const [],
    this.messages = const {},
    this.noMore = const {},
    this.summary = const {},
    this.presence = const {},
    this.typing = const {},
    this.guildId,
    this.channelId,
    this.members = const {},
  });

  static const Object _unset = Object();

  ChatState copyWith({
    User? me,
    bool? loading,
    String? error,
    List<Guild>? guilds,
    Map<String, List<Channel>>? channels,
    List<DMSession>? dms,
    Map<String, List<Message>>? messages,
    Set<String>? noMore,
    Map<String, ChannelSummary>? summary,
    Map<String, String>? presence,
    Map<String, List<String>>? typing,
    Object? guildId = _unset,
    Object? channelId = _unset,
    Map<String, List<MemberInfo>>? members,
    bool clearError = false,
  }) {
    return ChatState(
      me: me ?? this.me,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      guilds: guilds ?? this.guilds,
      channels: channels ?? this.channels,
      dms: dms ?? this.dms,
      messages: messages ?? this.messages,
      noMore: noMore ?? this.noMore,
      summary: summary ?? this.summary,
      presence: presence ?? this.presence,
      typing: typing ?? this.typing,
      // 传 null 表示显式清空（如退出服务器后），不传保持原值
      guildId: guildId == _unset ? this.guildId : guildId as String?,
      channelId: channelId == _unset ? this.channelId : channelId as String?,
      members: members ?? this.members,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  Timer? _typingThrottle;
  final Map<String, Timer> _typingClear = {};
  Timer? _presenceTimer;

  @override
  ChatState build() {
    final api = ref.watch(apiProvider);
    final gw = ref.watch(gatewayProvider);
    if (api == null || gw == null) {
      // 未登录：清空状态
      _cancelTimers();
      return const ChatState();
    }
    // WS 事件 → 状态更新
    final sub = gw.events.listen(_onEvent);
    // 每次（重新）连上后重同步在线状态：断线期间的 PRESENCE/MEMBER 事件会丢失，
    // 不补拉就会停在旧快照（表现为「明明在线却显示离线」）
    final openSub = gw.onOpen.listen((_) => _resyncPresence());
    // 兜底：每分钟刷新一次成员在线状态（防事件丢失/时钟漂移导致状态滞留）
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) => _resyncPresence());
    ref.onDispose(() {
      sub.cancel();
      openSub.cancel();
      _cancelTimers();
    });
    // 首次（或重新登录）进入时引导加载
    Future.microtask(_bootstrap);
    return const ChatState(loading: true);
  }

  /// 重新拉取当前服务器成员（在线状态随 REST 返回），并刷新未读汇总。
  Future<void> _resyncPresence() async {
    final gid = state.guildId;
    if (gid == null) return;
    await _loadMembers(gid);
  }

  void _cancelTimers() {
    _typingThrottle?.cancel();
    _presenceTimer?.cancel();
    _presenceTimer = null;
    for (final t in _typingClear.values) {
      t.cancel();
    }
    _typingClear.clear();
  }

  ApiClient get _api => ref.read(apiProvider)!;
  Gateway get _gw => ref.read(gatewayProvider)!;

  // ---------- 引导 ----------

  Future<void> _bootstrap() async {
    try {
      final me = await _api.me();
      final results = await Future.wait([
        _api.listGuilds(),
        _api.listDMs(),
        _api.summary(),
      ]);
      final guilds = results[0] as List<Guild>;
      final dms = results[1] as List<DMSession>;
      final summary = results[2] as List<ChannelSummary>;

      // 预取各服务器频道与成员（规模小，直接并行）
      final channelsMap = <String, List<Channel>>{};
      final membersMap = <String, List<MemberInfo>>{};
      final presence = <String, String>{};
      await Future.wait(guilds.map((g) async {
        try {
          channelsMap[g.id] = await _api.listChannels(g.id);
          final ms = await _api.listMembers(g.id);
          membersMap[g.id] = ms;
          for (final m in ms) {
            presence[m.user.id] = m.status;
          }
        } catch (_) {}
      }));

      state = state.copyWith(
        loading: false,
        me: me,
        guilds: guilds,
        dms: dms,
        channels: channelsMap,
        members: membersMap,
        presence: presence,
        summary: {for (final s in summary) s.channelId: s},
        // 默认选中第一个服务器的第一个频道
        guildId: guilds.isNotEmpty ? state.guildId ?? guilds.first.id : null,
      );
      if (state.channelId == null && guilds.isNotEmpty) {
        final chs = channelsMap[guilds.first.id];
        if (chs != null && chs.isNotEmpty) {
          await selectChannel(chs.first.id);
        }
      }
    } on ApiException catch (e) {
      if (e.status == 401) {
        // token 失效
        await ref.read(tokenProvider.notifier).set(null);
        return;
      }
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: '初始化失败: $e');
    }
  }

  Future<void> refreshSummary() async {
    try {
      final s = await _api.summary();
      state = state.copyWith(summary: {for (final x in s) x.channelId: x});
    } catch (_) {}
  }

  // ---------- 选择 ----------

  Future<void> selectGuild(String guildId) async {
    state = state.copyWith(guildId: guildId, channelId: null);
    if (state.channels[guildId] == null) {
      try {
        final chs = await _api.listChannels(guildId);
        state = state.copyWith(channels: {...state.channels, guildId: chs});
      } catch (_) {}
    }
    if (state.members[guildId] == null) {
      _loadMembers(guildId);
    }
    final chs = state.channels[guildId];
    if (chs != null && chs.isNotEmpty) {
      await selectChannel(chs.first.id);
    }
  }

  void selectDMHome() {
    state = state.copyWith(guildId: null, channelId: null);
  }

  Future<void> _loadMembers(String guildId) async {
    try {
      final ms = await _api.listMembers(guildId);
      final presence = Map.of(state.presence);
      for (final m in ms) {
        presence[m.user.id] = m.status;
      }
      state = state.copyWith(
        members: {...state.members, guildId: ms},
        presence: presence,
      );
    } catch (_) {}
  }

  Future<void> selectChannel(String channelId) async {
    state = state.copyWith(channelId: channelId);
    if (state.messages[channelId] == null) {
      await _loadMessages(channelId);
    }
    await _markRead(channelId);
  }

  Future<void> _loadMessages(String channelId, {String? before}) async {
    try {
      final msgs = await _api.listMessages(channelId, before: before);
      final list = List.of(state.messages[channelId] ?? const <Message>[]);
      final existing = {for (final m in list) m.id};
      final noMore = Set.of(state.noMore);
      if (before == null) {
        // 服务端 ListMessages 已返回时间正序（旧→新），这里不能再 reversed，
        // 否则历史记录会倒序显示（新消息在上、旧消息在下）。UI 用 reverse:true 列表，
        // 列表末尾（最新）渲染在最下方。
        list
          ..clear()
          ..addAll(msgs);
      } else {
        // 更早的一页同样是正序，插到列表头部保持整体升序
        final older = msgs.where((m) => !existing.contains(m.id)).toList();
        list.insertAll(0, older);
      }
      if (msgs.length < 50) noMore.add(channelId);
      state = state.copyWith(
        messages: {...state.messages, channelId: list},
        noMore: noMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    } catch (e) {
      state = state.copyWith(error: '加载消息失败: $e');
    }
  }

  Future<void> loadOlder(String channelId) async {
    if (state.noMore.contains(channelId)) return;
    final list = state.messages[channelId];
    if (list == null || list.isEmpty) return;
    await _loadMessages(channelId, before: list.first.id);
  }

  Future<void> _markRead(String channelId) async {
    final list = state.messages[channelId];
    if (list == null || list.isEmpty) return;
    final last = list.last;
    final cur = state.summary[channelId];
    if (cur != null && (cur.unread == 0 && cur.lastMessageId == last.id)) return;
    state = state.copyWith(summary: {
      ...state.summary,
      channelId: ChannelSummary(
        channelId: channelId, lastMessageId: last.id, unread: 0, mentions: 0),
    });
    try {
      await _api.markRead(channelId, last.id);
    } catch (_) {}
  }

  // ---------- 消息操作 ----------

  Future<void> send(String channelId, String content, {String? replyToId}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      final msg = await _api.sendMessage(channelId, trimmed, replyToId: replyToId);
      _appendMessage(msg);
      _markRead(channelId);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  void _appendMessage(Message msg) {
    final list = List.of(state.messages[msg.channelId] ?? const <Message>[]);
    if (list.any((m) => m.id == msg.id)) return; // WS 重复投递去重
    list.add(msg);
    // 作者信息兜底（WS 事件可能不带 author）
    msg.author ??= _userOf(msg.authorId) ?? state.me;
    state = state.copyWith(messages: {...state.messages, msg.channelId: list});
  }

  User? _userOf(String id) {
    for (final ms in state.members.values) {
      for (final m in ms) {
        if (m.user.id == id) return m.user;
      }
    }
    for (final d in state.dms) {
      if (d.other.id == id) return d.other;
    }
    return null;
  }

  Future<void> editMessage(String messageId, String content) async {
    try {
      final updated = await _api.editMessage(messageId, content);
      final list = List.of(state.messages[updated.channelId] ?? const <Message>[]);
      final i = list.indexWhere((m) => m.id == messageId);
      if (i >= 0) {
        list[i].content = updated.content;
        list[i].editedAt = updated.editedAt;
        state = state.copyWith(messages: {...state.messages, updated.channelId: list});
      }
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      String? cid;
      for (final e in state.messages.entries) {
        if (e.value.any((m) => m.id == messageId)) cid = e.key;
      }
      if (cid == null) return;
      await _api.deleteMessage(messageId);
      final l2 = List.of(state.messages[cid]!);
      l2.removeWhere((m) => m.id == messageId);
      state = state.copyWith(messages: {...state.messages, cid: l2});
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  Future<void> toggleReaction(String messageId, String emoji) async {
    String? cid;
    Message? msg;
    for (final e in state.messages.entries) {
      for (final m in e.value) {
        if (m.id == messageId) {
          cid = e.key;
          msg = m;
        }
      }
    }
    if (cid == null || msg == null) return;
    final idx = msg.reactions.indexWhere((r) => r.emoji == emoji);
    final mine = idx >= 0 && msg.reactions[idx].mine;
    try {
      if (mine) {
        await _api.removeReaction(messageId, emoji);
      } else {
        await _api.addReaction(messageId, emoji);
      }
      // 本地乐观更新（WS 事件也会到达，按 userId 判定幂等）
      _applyReaction(messageId, emoji, state.me!.id, add: !mine, isMine: true);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  void _applyReaction(String messageId, String emoji, String userId,
      {required bool add, required bool isMine}) {
    String? cid;
    Message? msg;
    for (final e in state.messages.entries) {
      for (final m in e.value) {
        if (m.id == messageId) {
          cid = e.key;
          msg = m;
        }
      }
    }
    if (cid == null || msg == null) return;
    final reactions = List.of(msg.reactions);
    final i = reactions.indexWhere((r) => r.emoji == emoji);
    if (add) {
      if (i >= 0) {
        if (isMine && reactions[i].mine) return; // 幂等
        reactions[i] = ReactionSummary(
          emoji: emoji, count: reactions[i].count + 1, mine: reactions[i].mine || isMine);
      } else {
        reactions.add(ReactionSummary(emoji: emoji, count: 1, mine: isMine));
      }
    } else {
      if (i < 0) return;
      final wasMine = reactions[i].mine;
      if (reactions[i].count <= 1) {
        reactions.removeAt(i);
      } else {
        reactions[i] = ReactionSummary(
          emoji: emoji, count: reactions[i].count - 1, mine: wasMine && !isMine);
      }
    }
    msg.reactions = reactions;
    state = state.copyWith(messages: {...state.messages, cid: List.of(state.messages[cid]!)});
  }

  // ---------- typing ----------

  void notifyTyping(String channelId) {
    // 3 秒节流：首次立即发送，冷却期内忽略
    if (_typingThrottle != null && _typingThrottle!.isActive) return;
    _gw.sendTyping(channelId);
    _typingThrottle?.cancel();
    _typingThrottle = Timer(const Duration(seconds: 3), () {});
  }

  // ---------- DM ----------

  Future<DMSession?> openDM(String userId) async {
    try {
      final dm = await _api.openDM(userId);
      final exists = state.dms.any((d) => d.id == dm.id);
      final dms = exists
          ? state.dms
          : [dm, ...state.dms];
      state = state.copyWith(dms: dms, guildId: null, channelId: dm.id);
      if (!state.messages.containsKey(dm.id)) {
        await _loadMessages(dm.id);
      }
      await _markRead(dm.id);
      return dm;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return null;
    }
  }

  // ---------- 服务器/频道管理 ----------

  Future<void> createGuild(String name) async {
    try {
      final (g, chs) = await _api.createGuild(name);
      state = state.copyWith(
        guilds: [...state.guilds, g],
        channels: {...state.channels, g.id: chs},
        members: {...state.members, g.id: [MemberInfo(user: state.me!, status: 'online')]},
        error: null,
      );
      await selectGuild(g.id);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  Future<String?> joinByInvite(String code) async {
    try {
      final g = await _api.joinByInvite(code);
      if (!state.guilds.any((x) => x.id == g.id)) {
        state = state.copyWith(guilds: [...state.guilds, g]);
      }
      await selectGuild(g.id);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> leaveGuild(String guildId, {String? successorId}) async {
    try {
      await _api.leaveGuild(guildId, successorId: successorId);
      _removeGuildLocal(guildId);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  Future<void> deleteGuild(String guildId) async {
    try {
      await _api.deleteGuild(guildId);
      _removeGuildLocal(guildId);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  void _removeGuildLocal(String guildId) {
    final guilds = state.guilds.where((g) => g.id != guildId).toList();
    final channels = Map.of(state.channels)..remove(guildId);
    final members = Map.of(state.members)..remove(guildId);
    final removedChannelIds = (channels[guildId] ?? const <Channel>[]).map((c) => c.id).toSet();
    final summary = Map.of(state.summary)
      ..removeWhere((cid, _) => removedChannelIds.contains(cid));
    state = state.copyWith(
      guilds: guilds, channels: channels, members: members, summary: summary,
      guildId: null, channelId: null,
    );
    if (guilds.isNotEmpty) selectGuild(guilds.first.id);
  }

  Future<void> createChannel(String guildId, String name, String category) async {
    try {
      final ch = await _api.createChannel(guildId, name, category);
      final chs = List.of(state.channels[guildId] ?? const <Channel>[])..add(ch);
      state = state.copyWith(channels: {...state.channels, guildId: chs});
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  Future<void> deleteChannel(String channelId) async {
    try {
      await _api.deleteChannel(channelId);
      final channels = <String, List<Channel>>{};
      for (final e in state.channels.entries) {
        channels[e.key] = e.value.where((c) => c.id != channelId).toList();
      }
      state = state.copyWith(channels: channels);
      if (state.channelId == channelId) {
        state = state.copyWith(channelId: null);
        final chs = state.channels[state.guildId];
        if (chs != null && chs.isNotEmpty) await selectChannel(chs.first.id);
      }
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  // ---------- WS 事件处理 ----------

  void _onEvent(WSEvent ev) {
    switch (ev.t) {
      case 'MESSAGE_CREATE':
        final msg = Message.fromJson(ev.d);
        _appendMessage(msg);
        if (msg.channelId == state.channelId) {
          _markRead(msg.channelId);
        } else {
          // 未读 +1；@我 则 mentions +1
          final cur = state.summary[msg.channelId];
          final mentioned = state.me != null &&
              (msg.content.contains('@${state.me!.username}'));
          state = state.copyWith(summary: {
            ...state.summary,
            msg.channelId: ChannelSummary(
              channelId: msg.channelId,
              lastMessageId: msg.id,
              unread: (cur?.unread ?? 0) + 1,
              mentions: (cur?.mentions ?? 0) + (mentioned ? 1 : 0),
            ),
          });
        }
      case 'MESSAGE_UPDATE':
        final m = Message.fromJson(ev.d);
        final list = List.of(state.messages[m.channelId] ?? const <Message>[]);
        final i = list.indexWhere((x) => x.id == m.id);
        if (i >= 0) {
          list[i].content = m.content;
          list[i].editedAt = m.editedAt;
          state = state.copyWith(messages: {...state.messages, m.channelId: list});
        }
      case 'MESSAGE_DELETE':
        final d = ev.d as Map<String, dynamic>;
        final cid = d['channelId'] as String;
        final id = d['id'] as String;
        final list = List.of(state.messages[cid] ?? const <Message>[]);
        list.removeWhere((m) => m.id == id);
        state = state.copyWith(messages: {...state.messages, cid: list});
      case 'REACTION_ADD':
        final d = ev.d as Map<String, dynamic>;
        _applyReaction(d['messageId'] as String, d['emoji'] as String,
            d['userId'] as String, add: true, isMine: d['userId'] == state.me?.id);
      case 'REACTION_REMOVE':
        final d = ev.d as Map<String, dynamic>;
        _applyReaction(d['messageId'] as String, d['emoji'] as String,
            d['userId'] as String, add: false, isMine: d['userId'] == state.me?.id);
      case 'TYPING_START':
        final d = ev.d as Map<String, dynamic>;
        final cid = d['channelId'] as String;
        final uname = d['username'] as String;
        if (d['userId'] == state.me?.id) return;
        final list = List.of(state.typing[cid] ?? const <String>[]);
        if (!list.contains(uname)) list.add(uname);
        state = state.copyWith(typing: {...state.typing, cid: list});
        _typingClear[cid]?.cancel();
        _typingClear[cid] = Timer(const Duration(seconds: 6), () {
          final l = List.of(state.typing[cid] ?? const <String>[])..remove(uname);
          state = state.copyWith(typing: {...state.typing, cid: l});
        });
      case 'PRESENCE_UPDATE':
        final d = ev.d as Map<String, dynamic>;
        state = state.copyWith(presence: {
          ...state.presence,
          d['userId'] as String: d['status'] as String,
        });
      case 'CHANNEL_CREATED':
        final ch = Channel.fromJson(ev.d);
        final chs = List.of(state.channels[ch.guildId] ?? const <Channel>[]);
        if (!chs.any((c) => c.id == ch.id)) chs.add(ch);
        state = state.copyWith(channels: {...state.channels, ch.guildId: chs});
      case 'CHANNEL_DELETED':
        final d = ev.d as Map<String, dynamic>;
        final gid = d['guildId'] as String;
        final cid = d['channelId'] as String;
        final chs = (state.channels[gid] ?? const <Channel>[]).where((c) => c.id != cid).toList();
        state = state.copyWith(channels: {...state.channels, gid: chs});
        if (state.channelId == cid) {
          state = state.copyWith(channelId: null);
          if (chs.isNotEmpty) selectChannel(chs.first.id);
        }
      case 'MEMBER_JOINED':
        final d = ev.d as Map<String, dynamic>;
        final gid = d['guildId'] as String;
        final u = User.fromJson(d['user']);
        final ms = List.of(state.members[gid] ?? const <MemberInfo>[]);
        if (!ms.any((m) => m.user.id == u.id)) {
          ms.add(MemberInfo(user: u, status: 'online'));
        }
        state = state.copyWith(members: {...state.members, gid: ms});
      case 'MEMBER_LEFT':
        final d = ev.d as Map<String, dynamic>;
        final gid = d['guildId'] as String;
        final uid = d['userId'] as String;
        final ms = (state.members[gid] ?? const <MemberInfo>[]).where((m) => m.user.id != uid).toList();
        state = state.copyWith(members: {...state.members, gid: ms});
      case 'GUILD_DELETED':
        // 所在服务器被解散：移除本地数据并切回首个可用服务器
        final gid = (ev.d as Map<String, dynamic>)['guildId'] as String;
        if (!state.guilds.any((g) => g.id == gid)) return;
        final guilds = state.guilds.where((g) => g.id != gid).toList();
        final channels = Map.of(state.channels)..remove(gid);
        final members = Map.of(state.members)..remove(gid);
        state = state.copyWith(
          guilds: guilds, channels: channels, members: members,
          guildId: null, channelId: null,
        );
        if (guilds.isNotEmpty) {
          selectGuild(guilds.first.id);
        }
      case 'DM_CREATED':
        final dm = DMSession.fromJson(ev.d);
        if (!state.dms.any((x) => x.id == dm.id)) {
          state = state.copyWith(dms: [dm, ...state.dms]);
        }
    }
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
