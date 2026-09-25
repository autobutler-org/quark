/// A chat channel the signed-in account belongs to, as
/// `GET /api/v0/chat/channels` lists it (#2415). With `?all=1` an admin also
/// gets the channels they are not in, which carry no [level] (#2422).
class ChatChannel {
  /// Builds a channel explicitly; tests use it.
  const ChatChannel({
    required this.id,
    required this.name,
    this.topic = '',
    this.isDefault = false,
    this.isPrivate = false,
    this.level,
  });

  /// The channel's id, the `/chat/:channelId` in its URL.
  final int id;

  /// The name shown after `#`.
  final String name;

  /// A line about what the channel is for; empty when it has none.
  final String topic;

  /// Whether this is the Quark's `general` channel, which everyone is in.
  final bool isDefault;

  /// Whether only its members can see it.
  final bool isPrivate;

  /// The caller's level on it, `read`, `write` or `owner`; null for a channel
  /// an admin can manage but is not in.
  final String? level;

  /// Whether the caller belongs to it, so can read it.
  bool get isMember => level != null && level!.isNotEmpty;

  /// Whether the caller owns it, so can rename, share and delete it.
  bool get isOwner => level == 'owner';

  /// Whether the caller may post: any level but `read`.
  bool get canWrite => level != 'read';

  /// Reads one channel.
  factory ChatChannel.fromJson(Map<String, dynamic> json) => ChatChannel(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    topic: json['topic'] as String? ?? '',
    isDefault: json['isDefault'] as bool? ?? false,
    isPrivate: json['isPrivate'] as bool? ?? false,
    level: json['level'] as String?,
  );
}

/// One row of a channel's members: an account, or a group with its accounts,
/// as `GET /api/v0/chat/channels/:id/members` lists it.
class ChatMember {
  /// Builds a member explicitly; tests use it.
  const ChatMember({
    required this.name,
    required this.level,
    this.userId,
    this.groupId,
    this.builtin = false,
    this.avatarUpdatedAt,
    this.users = const [],
  });

  /// The account's id, null for a group.
  final int? userId;

  /// The group's id, null for an account.
  final int? groupId;

  /// The username or group name.
  final String name;

  /// Whether this is the Quark's own `everyone` group.
  final bool builtin;

  /// `read`, `write` or `owner`.
  final String level;

  /// The account's profile picture version, null without one.
  final int? avatarUpdatedAt;

  /// A group's accounts; empty for an account.
  final List<ChatMemberUser> users;

  /// Reads one member row.
  factory ChatMember.fromJson(Map<String, dynamic> json) => ChatMember(
    userId: (json['userId'] as num?)?.toInt(),
    groupId: (json['groupId'] as num?)?.toInt(),
    name: json['name'] as String? ?? '',
    builtin: json['builtin'] as bool? ?? false,
    level: json['level'] as String? ?? 'read',
    avatarUpdatedAt: (json['avatarUpdatedAt'] as num?)?.toInt(),
    users: [
      for (final u in json['users'] as List? ?? const [])
        ChatMemberUser.fromJson(u as Map<String, dynamic>),
    ],
  );
}

/// An account listed under a group in [ChatMember.users].
class ChatMemberUser {
  /// Builds one explicitly; tests use it.
  const ChatMemberUser({
    required this.id,
    required this.username,
    this.avatarUpdatedAt,
  });

  /// The account's id.
  final int id;

  /// The account's username.
  final String username;

  /// The account's profile picture version, null without one.
  final int? avatarUpdatedAt;

  /// Reads one.
  factory ChatMemberUser.fromJson(Map<String, dynamic> json) => ChatMemberUser(
    id: (json['id'] as num).toInt(),
    username: json['username'] as String? ?? '',
    avatarUpdatedAt: (json['avatarUpdatedAt'] as num?)?.toInt(),
  );
}
