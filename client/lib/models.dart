/// 数据模型：与 Go 后端的 JSON 结构一一对应。
library;

// Go time.Time 可能输出 7-9 位小数秒（RFC3339Nano），Dart 只认 ≤6 位，做一次归一化。
DateTime parseGoTime(String s) {
  final i = s.indexOf('.');
  if (i > 0) {
    var frac = '';
    var j = i + 1;
    while (j < s.length && s.codeUnitAt(j) >= 0x30 && s.codeUnitAt(j) <= 0x39) {
      frac += s[j];
      j++;
    }
    if (frac.length > 6) {
      s = '${s.substring(0, i)}.${frac.substring(0, 6)}${s.substring(j)}';
    }
  }
  return DateTime.parse(s).toLocal();
}

class User {
  final String id;
  final String username;
  final String discriminator;
  final String avatarColor;
  final String avatarUrl;
  const User({
    required this.id,
    required this.username,
    required this.discriminator,
    required this.avatarColor,
    this.avatarUrl = '',
  });

  String get tag => '$username#$discriminator';

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        username: j['username'] as String,
        discriminator: j['discriminator'] as String,
        avatarColor: j['avatarColor'] as String? ?? '#5865F2',
        avatarUrl: j['avatarUrl'] as String? ?? '',
      );
}

class Guild {
  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final String iconColor;
  const Guild({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    required this.iconColor,
  });

  factory Guild.fromJson(Map<String, dynamic> j) => Guild(
        id: j['id'] as String,
        name: j['name'] as String,
        ownerId: j['ownerId'] as String,
        inviteCode: j['inviteCode'] as String,
        iconColor: j['iconColor'] as String? ?? '#5865F2',
      );
}

class Channel {
  final String id;
  final String guildId;
  final String name;
  final String category;
  const Channel({
    required this.id,
    required this.guildId,
    required this.name,
    required this.category,
  });

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        id: j['id'] as String,
        guildId: j['guildId'] as String,
        name: j['name'] as String,
        category: j['category'] as String? ?? '',
      );
}

class ReactionSummary {
  final String emoji;
  final int count;
  final bool mine;
  const ReactionSummary({
    required this.emoji,
    required this.count,
    required this.mine,
  });

  factory ReactionSummary.fromJson(Map<String, dynamic> j) => ReactionSummary(
        emoji: j['emoji'] as String,
        count: (j['count'] as num).toInt(),
        mine: j['mine'] as bool? ?? false,
      );
}

class Message {
  final String id;
  final String channelId;
  final String authorId;
  String content;
  final DateTime createdAt;
  DateTime? editedAt;
  User? author;
  List<ReactionSummary> reactions;
  String replyToId;
  MessageReply? replyTo;

  Message({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.editedAt,
    this.author,
    List<ReactionSummary>? reactions,
    this.replyToId = '',
    this.replyTo,
  }) : reactions = reactions ?? const [];

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        channelId: j['channelId'] as String,
        authorId: j['authorId'] as String,
        content: j['content'] as String,
        createdAt: parseGoTime(j['createdAt'] as String),
        editedAt: j['editedAt'] == null ? null : parseGoTime(j['editedAt'] as String),
        author: j['author'] == null ? null : User.fromJson(j['author']),
        reactions: (j['reactionSummaries'] as List?)
                ?.map((e) => ReactionSummary.fromJson(e))
                .toList(),
        replyToId: j['replyToId'] as String? ?? '',
        replyTo: j['replyTo'] == null ? null : MessageReply.fromJson(j['replyTo']),
      );
}

/// 被引用消息的摘要（服务端截断到 ~120 字符）。
class MessageReply {
  final String id;
  final String authorName;
  final String authorColor;
  final String content;
  const MessageReply({
    required this.id,
    required this.authorName,
    required this.authorColor,
    required this.content,
  });

  factory MessageReply.fromJson(Map<String, dynamic> j) => MessageReply(
        id: j['id'] as String,
        authorName: j['authorName'] as String? ?? '未知用户',
        authorColor: j['authorColor'] as String? ?? '#5865F2',
        content: j['content'] as String? ?? '',
      );
}

class DMSession {
  final String id;
  final User other;
  final String lastMessageId;
  const DMSession({required this.id, required this.other, required this.lastMessageId});

  factory DMSession.fromJson(Map<String, dynamic> j) => DMSession(
        id: j['id'] as String,
        other: User.fromJson((j['users'] as List).first),
        lastMessageId: j['lastMessageId'] as String? ?? '',
      );
}

class MemberInfo {
  final User user;
  final String status; // online / idle / offline
  const MemberInfo({required this.user, required this.status});

  factory MemberInfo.fromJson(Map<String, dynamic> j) => MemberInfo(
        user: User.fromJson(j),
        status: j['status'] as String? ?? 'offline',
      );
}

class ChannelSummary {
  final String channelId;
  final String lastMessageId;
  final int unread;
  final int mentions;
  const ChannelSummary({
    required this.channelId,
    required this.lastMessageId,
    required this.unread,
    required this.mentions,
  });

  factory ChannelSummary.fromJson(Map<String, dynamic> j) => ChannelSummary(
        channelId: j['channelId'] as String,
        lastMessageId: j['lastMessageId'] as String,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
        mentions: (j['mentions'] as num?)?.toInt() ?? 0,
      );
}
