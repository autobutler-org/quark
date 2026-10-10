import 'package:quark_widgets/quark_widgets.dart';

/// A chat channel the signed-in account can see, as
/// `GET /api/v0/chat/channels` lists it (#2415). With `?all=1` an admin also
/// gets the channels they are not in, which carry an empty [permissions] set
/// (#2422).
class ChatChannel {
  /// Builds a channel explicitly; tests use it.
  const ChatChannel({
    required this.id,
    required this.name,
    this.topic = '',
    this.isDefault = false,
    this.isPrivate = false,
    this.permissions = const {},
    this.createdBy,
    this.unreadCount = 0,
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

  /// What the caller may do here: the union of every row that reaches them,
  /// as the Quark worked it out. A hint for the UI only; the Quark enforces
  /// it. Empty for a channel an admin can manage but is not in.
  final Set<ChatPermission> permissions;

  /// The account that created the channel, whose row only an admin can
  /// remove or lower; null for `general` and once that account is deleted.
  final int? createdBy;

  /// How many messages other people wrote here after the caller's read
  /// marker, deleted ones left out (#2424). Zero on a channel the caller
  /// doesn't read.
  final int unreadCount;

  /// Whether the caller has any row here. A channel an admin lists without
  /// being in it has none.
  bool get isMember => permissions.isNotEmpty;

  /// Whether the caller is in the conversation: reads it and holds its key.
  /// A channel listed without it is one the caller only manages.
  bool get canRead => permissions.contains(ChatPermission.readMessages);

  /// Whether the caller may post.
  bool get canSend => permissions.contains(ChatPermission.sendMessages);

  /// Reads one channel. Permission names this version doesn't know are
  /// dropped.
  factory ChatChannel.fromJson(Map<String, dynamic> json) => ChatChannel(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    topic: json['topic'] as String? ?? '',
    isDefault: json['isDefault'] as bool? ?? false,
    isPrivate: json['isPrivate'] as bool? ?? false,
    permissions: chatPermissionsFromJson(json['permissions']),
    createdBy: (json['createdBy'] as num?)?.toInt(),
    unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
  );
}

/// Where the signed-in account's read marker stands in one channel (#2424),
/// as `PUT /api/v0/chat/channels/:id/read` answers and a
/// `chat_read_marker_changed` event carries.
class ChatReadMarker {
  /// Builds a marker explicitly; tests use it.
  const ChatReadMarker({
    required this.channelId,
    required this.lastReadMessageId,
    required this.unreadCount,
  });

  /// The channel the marker is in.
  final int channelId;

  /// The newest message the account has read there.
  final int lastReadMessageId;

  /// How many messages from other people come after it.
  final int unreadCount;

  /// Reads one marker.
  factory ChatReadMarker.fromJson(Map<String, dynamic> json) => ChatReadMarker(
    channelId: (json['channelId'] as num).toInt(),
    lastReadMessageId: (json['lastReadMessageId'] as num?)?.toInt() ?? 0,
    unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
  );
}

/// The permissions in a JSON array of names, skipping any this version
/// doesn't know.
Set<ChatPermission> chatPermissionsFromJson(Object? names) => {
  for (final name in names is List ? names : const [])
    if (name is String) ?ChatPermission.byId(name),
};

/// One row of a channel's members: an account, or a group with its accounts,
/// as `GET /api/v0/chat/channels/:id/members` lists it.
class ChatMember {
  /// Builds a member explicitly; tests use it.
  const ChatMember({
    required this.name,
    required this.permissions,
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

  /// What this row lets its account or group do.
  final Set<ChatPermission> permissions;

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
    permissions: chatPermissionsFromJson(json['permissions']),
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
