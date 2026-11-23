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
  /// 别人在其它频道 @ 我时的提示文案（UI 弹 SnackBar 用）；mentionTick 每次+1 触发
  final String? mentionText;
  final int mentionTick;
  /// 跳转目标高亮（搜索结果/引用回复定位）；jumpTick 每次跳转 +1 触发滚动
  final String? highlightId;
  final int jumpTick;

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
    this.mentionText,
    this.mentionTick = 0,
    this.highlightId,
    this.jumpTick = 0,
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
    String? mentionText,
    int? mentionTick,
    String? highlightId,
    int? jumpTick,
    bool clearHighlight = false,
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
      mentionText: mentionText ?? this.mentionText,
      mentionTick: mentionTick ?? this.mentionTick,
      highlightId: clearHighlight ? null : (highlightId ?? this.highlightId),
      jumpTick: jumpTick ?? this.jumpTick,
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
    final openSub = gw.onOpen.listen((_) {
      _resyncPresence();
      // 断线期间的 MESSAGE_CREATE 也会丢：重连后补拉当前频道最新一页。
      // _loadMessages 是按 id 合并，不会冲掉本地已有的消息。
      final cid = state.channelId;
      if (cid != null) _loadMessages(cid);
    });
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
    // 无条件拉最新一页：WS 推送会给未打开的频道预置残缺列表（messages 非 null 但没做过
    // 完整分页），若按 null 判断跳过，noMore 永远不会标记 → 顶部转圈不停 + 历史缺失。
    await _loadMessages(channelId);
    await _markRead(channelId);
  }

  /// 跳转到指定消息：必要时切频道、拉取上下文、滚动并高亮。
  Future<void> jumpToMessage(String channelId, String messageId) async {
    final needSwitch = state.channelId != channelId;
    if (needSwitch) {
      state = state.copyWith(channelId: channelId);
    }
    final list = state.messages[channelId] ?? const <Message>[];
    if (needSwitch || !list.any((m) => m.id == messageId)) {
      await _loadMessagesAround(channelId, messageId);
      await _markRead(channelId);
    }
    state = state.copyWith(
      highlightId: messageId,
      jumpTick: state.jumpTick + 1,
    );
  }

  Future<void> _loadMessagesAround(String channelId, String messageId) async {
    try {
      final msgs = await _api.listMessagesAround(channelId, messageId);
      // 上下文页不知道前后边界，清掉 noMore 让继续滚动时还能加载
      final noMore = Set.of(state.noMore)..remove(channelId);
      state = state.copyWith(
        messages: {...state.messages, channelId: msgs},
        noMore: noMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  void clearHighlight() {
    if (state.highlightId != null) {
      state = state.copyWith(clearHighlight: true);
    }
  }

  Future<void> _loadMessages(String channelId, {String? before}) async {
    try {
      final msgs = await _api.listMessages(channelId, before: before);
      final list = List.of(state.messages[channelId] ?? const <Message>[]);
      final existing = {for (final m in list) m.id};
      final noMore = Set.of(state.noMore);
      if (before == null) {
        // 服务端 ListMessages 已返回时间正序（旧→新）。这里合并而不是整表替换：
        // ① 保留已向上翻页加载的更早消息（id < 本页最旧）；
        // ② 保留 fetch 期间 WS 新到的更晚消息（id > 本页最新）——
        //   整表替换会把这些消息冲掉（fetch 快照比它旧），造成消息丢失；
        // ③ 合并按 id 幂等，两个并发 fetch 响应乱序到达也不会回退状态。
        if (msgs.isNotEmpty) {
          final fetchedIds = {for (final m in msgs) m.id};
          final oldest = msgs.first.id, newest = msgs.last.id;
          final older = list
              .where((m) => !fetchedIds.contains(m.id) && m.id.compareTo(oldest) < 0)
              .toList();
          final newer = list
              .where((m) => !fetchedIds.contains(m.id) && m.id.compareTo(newest) > 0)
              .toList();
          list
            ..clear()
            ..addAll(older)
            ..addAll(msgs)
            ..addAll(newer);
        }
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

  /// 发送消息；返回 null 表示成功，否则为给用户看的错误文案
  ///（如 429 冷却「发言太快」——输入框会保留原文让用户重试）。
  Future<String?> send(String channelId, String content, {String? replyToId}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    try {
      final msg = await _api.sendMessage(channelId, trimmed, replyToId: replyToId);
      _appendMessage(msg);
      _markRead(channelId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return '发送失败，请检查网络';
    }
  }

  void _appendMessage(Message msg) {
    final list = List.of(state.messages[msg.channelId] ?? const <Message>[]);
    if (list.any((m) => m.id == msg.id)) return; // WS 重复投递去重
    // 按 ID（UUIDv7 时间有序，字典序=时间序）插到正确位置，而不是盲目 append：
    // 多端同时发消息时 REST 响应 / WS 事件可能交错到达，append 会把后发的
    // 消息放到先发的之前（表现为消息乱序）。正常情况下新消息 ID 最大，仍走末尾。
    var i = list.length;
    while (i > 0 && list[i - 1].id.compareTo(msg.id) > 0) {
      i--;
    }
    list.insert(i, msg);
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
      // 同 selectChannel：无条件拉最新一页，避免 WS 预投递的残缺列表挡住完整历史
      await _loadMessages(dm.id);
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

  /// 修改服务器名称/图标色（仅所有者）；返回错误文案或 null。
  Future<String?> updateGuild(Guild g, {String? name, String? iconColor}) async {
    try {
      final updated = await _api.updateGuild(g.id, name: name, iconColor: iconColor);
      _applyGuildUpdate(updated);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  void _applyGuildUpdate(Guild g) {
    state = state.copyWith(
      guilds: state.guilds.map((x) => x.id == g.id ? g : x).toList(),
    );
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

  Future<void> createChannel(String guildId, String name, String category,
      {bool ownerOnly = false}) async {
    try {
      final ch = await _api.createChannel(guildId, name, category, ownerOnly: ownerOnly);
      // CHANNEL_CREATED 的 WS 事件通常先于本 REST 响应到达（v1.3.4 投递串行化后必然如此），
      // 那边已把频道加进列表；这里必须按 id 去重，否则出现两个同名频道
      final chs = List.of(state.channels[guildId] ?? const <Channel>[]);
      if (!chs.any((c) => c.id == ch.id)) chs.add(ch);
      state = state.copyWith(channels: {...state.channels, guildId: chs});
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  /// 修改频道（改名/分组/发言权限）；仅频道创建者或服务器所有者。
  Future<String?> updateChannel(Channel ch,
      {String? name, String? category, String? speakMode, List<String>? allowedSpeakers}) async {
    try {
      final updated = await _api.updateChannel(ch.id,
          name: name, category: category, speakMode: speakMode, allowedSpeakers: allowedSpeakers);
      _applyChannelUpdate(updated);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  void _applyChannelUpdate(Channel updated) {
    final chs = List.of(state.channels[updated.guildId] ?? const <Channel>[]);
    final i = chs.indexWhere((c) => c.id == updated.id);
    if (i >= 0) chs[i] = updated;
    state = state.copyWith(channels: {...state.channels, updated.guildId: chs});
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

  /// 本机修改个人资料后，把新资料写回状态（me / 成员列表 / 历史消息作者）。
  void applyMe(User newMe) {
    if (state.me == null) return;
    _applyUser(newMe);
  }

  /// 某用户资料变化：同步 me、成员列表、私信对端、以及所有历史消息里的 author。
  /// 之前只更新了前三个，聊天记录里的头像/名字要重新登录才刷新（用户反馈）。
  void _applyUser(User u) {
    final members = <String, List<MemberInfo>>{};
    for (final e in state.members.entries) {
      members[e.key] = e.value
          .map((m) => m.user.id == u.id ? MemberInfo(user: u, status: m.status) : m)
          .toList();
    }
    final dms = state.dms
        .map((d0) => d0.other.id == u.id
            ? DMSession(id: d0.id, other: u, lastMessageId: d0.lastMessageId)
            : d0)
        .toList();
    // 历史消息：Message.author 是可变的，替换后需要换新的 List 触发刷新
    final messages = <String, List<Message>>{};
    for (final e in state.messages.entries) {
      var changed = false;
      final list = e.value.map((m) {
        if (m.author?.id == u.id) {
          changed = true;
          m.author = u;
        }
        return m;
      }).toList();
      messages[e.key] = changed ? list : e.value;
    }
    state = state.copyWith(
      members: members,
      dms: dms,
      me: state.me?.id == u.id ? u : null,
      messages: messages,
    );
  }

  /// 频道/私信的显示名（提及提示用）。
  String _channelDisplayName(String channelId) {
    final dm = state.dms.where((d) => d.id == channelId).firstOrNull;
    if (dm != null) return dm.other.username;
    for (final chs in state.channels.values) {
      for (final c in chs) {
        if (c.id == channelId) return '#${c.name}';
      }
    }
    return '频道';
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
              (msg.content.contains('@${state.me!.username}') ||
                  // 中文输入法可能敲出全角 ＠
                  msg.content.contains('＠${state.me!.username}'));
          state = state.copyWith(summary: {
            ...state.summary,
            msg.channelId: ChannelSummary(
              channelId: msg.channelId,
              lastMessageId: msg.id,
              unread: (cur?.unread ?? 0) + 1,
              mentions: (cur?.mentions ?? 0) + (mentioned ? 1 : 0),
            ),
          });
          if (mentioned) {
            // 被 @ 时给个即时提示（声音/桌面通知暂未做，先用 SnackBar）
            final name = _channelDisplayName(msg.channelId);
            state = state.copyWith(
              mentionText: '${msg.author?.username ?? '有人'} 在 $name 提到了你',
              mentionTick: state.mentionTick + 1,
            );
          }
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
      case 'CHANNEL_UPDATE':
        final ch = Channel.fromJson(ev.d);
        _applyChannelUpdate(ch);
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
      case 'GUILD_UPDATE':
        _applyGuildUpdate(Guild.fromJson(ev.d as Map<String, dynamic>));
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
      case 'USER_UPDATE':
        // 某成员改了名字/头像：成员列表、私信对端、我、以及历史消息里的作者引用
        final d = ev.d as Map<String, dynamic>;
        _applyUser(User.fromJson(d['user']));
    }
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
