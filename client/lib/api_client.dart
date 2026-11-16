import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// REST 客户端。所有请求自动带 token；错误统一抛 ApiException。
class ApiClient {
  String base;
  String? token;
  final http.Client _http = http.Client();

  ApiClient({required this.base, this.token});

  Uri _uri(String path, [Map<String, String>? q]) =>
      Uri.parse('$base/api$path').replace(queryParameters: q);

  /// 上传文件（v1.1），返回相对 URL（如 /uploads/202611/xxx.png）。
  Future<String> upload(List<int> bytes, String filename) async {
    final uri = Uri.parse('$base/api/upload');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    http.Response resp;
    try {
      resp = await http.Response.fromStream(await _http.send(req))
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw ApiException(0, '上传失败：无法连接服务器');
    }
    final text = utf8.decode(resp.bodyBytes);
    if (resp.statusCode >= 400) {
      String msg = '上传失败 (${resp.statusCode})';
      try {
        msg = (jsonDecode(text) as Map<String, dynamic>)['error'] as String? ?? msg;
      } catch (_) {}
      throw ApiException(resp.statusCode, msg);
    }
    return (jsonDecode(text) as Map<String, dynamic>)['url'] as String;
  }

  Future<dynamic> _call(String method, String path,
      {Map<String, String>? q, Object? body}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final uri = _uri(path, q);
    http.Response resp;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        req.body = jsonEncode(body);
      }
      resp = await http.Response.fromStream(await _http.send(req)).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ApiException(0, '无法连接服务器，请检查服务地址');
    }
    final text = utf8.decode(resp.bodyBytes);
    if (resp.statusCode >= 400) {
      String msg = '请求失败 (${resp.statusCode})';
      try {
        msg = (jsonDecode(text) as Map<String, dynamic>)['error'] as String? ?? msg;
      } catch (_) {}
      throw ApiException(resp.statusCode, msg);
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  // ---- auth ----
  Future<(String, User)> register(String username, String password) async {
    final r = await _call('POST', '/auth/register', body: {'username': username, 'password': password});
    return (r['token'] as String, User.fromJson(r['user']));
  }

  Future<(String, User)> login(String username, String password) async {
    final r = await _call('POST', '/auth/login', body: {'username': username, 'password': password});
    return (r['token'] as String, User.fromJson(r['user']));
  }

  Future<User> me() async => User.fromJson(await _call('GET', '/users/me'));

  Future<List<Map<String, dynamic>>> searchUsers(String q) async {
    final r = await _call('GET', '/users/search', q: {'q': q});
    return (r as List).cast<Map<String, dynamic>>();
  }

  // ---- guilds ----
  Future<List<Guild>> listGuilds() async =>
      ((await _call('GET', '/guilds')) as List).map((e) => Guild.fromJson(e)).toList();

  Future<(Guild, List<Channel>)> createGuild(String name) async {
    final r = await _call('POST', '/guilds', body: {'name': name});
    return (
      Guild.fromJson(r['guild']),
      (r['channels'] as List).map((e) => Channel.fromJson(e)).toList(),
    );
  }

  Future<List<Channel>> listChannels(String guildId) async => ((await _call('GET', '/guilds/$guildId/channels')) as List)
      .map((e) => Channel.fromJson(e))
      .toList();

  Future<Channel> createChannel(String guildId, String name, String category) async =>
      Channel.fromJson(await _call('POST', '/guilds/$guildId/channels', body: {'name': name, 'category': category}));

  Future<void> deleteChannel(String channelId) => _call('DELETE', '/channels/$channelId');

  Future<List<MemberInfo>> listMembers(String guildId) async => ((await _call('GET', '/guilds/$guildId/members')) as List)
      .map((e) => MemberInfo.fromJson(e))
      .toList();

  Future<void> leaveGuild(String guildId, {String? successorId}) =>
      _call('DELETE', '/guilds/$guildId/members/me',
          body: {if (successorId != null) 'successorId': successorId});

  Future<void> deleteGuild(String guildId) => _call('DELETE', '/guilds/$guildId');

  Future<String> regenInvite(String guildId) async =>
      (await _call('POST', '/guilds/$guildId/invites'))['inviteCode'] as String;

  Future<Map<String, dynamic>> invitePreview(String code) async =>
      await _call('GET', '/invites/$code') as Map<String, dynamic>;

  Future<Guild> joinByInvite(String code) async =>
      Guild.fromJson((await _call('POST', '/invites/$code/join'))['guild']);

  // ---- messages ----
  Future<List<Message>> listMessages(String channelId, {String? before, int limit = 50}) async {
    final r = await _call('GET', '/channels/$channelId/messages',
        q: {if (before != null) 'before': before, 'limit': '$limit'});
    return (r as List).map((e) => Message.fromJson(e)).toList();
  }

  Future<Message> sendMessage(String channelId, String content, {String? replyToId}) async =>
      Message.fromJson(await _call('POST', '/channels/$channelId/messages', body: {
        'content': content,
        if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
      }));

  Future<Message> editMessage(String messageId, String content) async =>
      Message.fromJson(await _call('PATCH', '/messages/$messageId', body: {'content': content}));

  Future<void> deleteMessage(String messageId) => _call('DELETE', '/messages/$messageId');

  Future<void> addReaction(String messageId, String emoji) =>
      _call('PUT', '/messages/$messageId/reactions', body: {'emoji': emoji});

  Future<void> removeReaction(String messageId, String emoji) =>
      _call('DELETE', '/messages/$messageId/reactions', q: {'emoji': emoji});

  Future<String> getReadState(String channelId) async =>
      (await _call('GET', '/channels/$channelId/read'))['lastReadMessageId'] as String;

  Future<void> markRead(String channelId, String messageId) =>
      _call('PUT', '/channels/$channelId/read', body: {'messageId': messageId});

  // ---- dms ----
  Future<List<DMSession>> listDMs() async =>
      ((await _call('GET', '/dms')) as List).map((e) => DMSession.fromJson(e)).toList();

  Future<DMSession> openDM(String userId) async => DMSession.fromJson(await _call('POST', '/dms/$userId'));

  // ---- summary ----
  Future<List<ChannelSummary>> summary() async =>
      ((await _call('GET', '/summary')) as List).map((e) => ChannelSummary.fromJson(e)).toList();
}
