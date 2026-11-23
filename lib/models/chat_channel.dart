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
    this.lastReadMessageId = 0,
    this.kind = channelKind,
    this.members = const [],
    this.forked = false,
    this.createdAt,
    this.anonymous = false,
    this.selfId,
  });

  /// [kind] of a named channel.
  static const channelKind = 'channel';

  /// [kind] of a direct message (#2423).
  static const directKind = 'dm';

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

  /// The caller's read marker here (#3543); 0 before the first read and on a
  /// channel the caller doesn't read.
  final int lastReadMessageId;

  /// [channelKind], or [directKind] for a direct message: no name, and
  /// people who never change.
  final String kind;

  /// A direct message's accounts, this one included; empty for a channel.
  final List<ChatMemberUser> members;

  /// Whether this direct message was started by adding people to an
  /// earlier one, whose messages stay there (#2423).
  final bool forked;

  /// When the channel was made; null from a Quark that sends none.
  final DateTime? createdAt;

  /// Whether its members see each other only by per-channel pseudonym and
  /// alias (#2949). Set when the channel is made and never changed; a direct
  /// message never is.
  final bool anonymous;

  /// The caller's own pseudonym in an anonymous channel it is in: the id it
  /// binds and signs wherever it would bind its account id elsewhere, and
  /// the one its messages, reactions and answers carry. Null in any other
  /// channel.
  final int? selfId;

  /// Whether this is a direct message.
  bool get isDirect => kind == directKind;

  /// Whether the caller has any row here. A channel an admin lists without
  /// being in it has none.
  bool get isMember => permissions.isNotEmpty;

  /// Whether the caller is in the conversation: reads it and holds its key.
  /// A channel listed without it is one the caller only manages.
  bool get canRead => permissions.contains(ChatPermission.readMessages);

  /// What a direct message is called, for account [me]: the other people's
  /// usernames, as `bob, cy`. `Only you` once everyone else's account is
  /// gone.
  String directName(int? me) {
    final others = [
      for (final m in members)
        if (m.id != me) m.username,
    ];
    return others.isEmpty ? 'Only you' : others.join(', ');
  }

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
    lastReadMessageId: (json['lastReadMessageId'] as num?)?.toInt() ?? 0,
    kind: json['kind'] as String? ?? channelKind,
    forked: json['forked'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    anonymous: json['anonymous'] as bool? ?? false,
    selfId: (json['selfId'] as num?)?.toInt(),
    members: [
      for (final m in json['members'] as List? ?? const [])
        ChatMemberUser.fromJson(m as Map<String, dynamic>),
    ],
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
/// as `GET /api/v0/chat/channels/:id/members` lists it. In an anonymous
/// channel (#2949) a caller without `manage_members` who isn't an admin gets
/// groups without [users], then one account row per person any row reaches,
/// carrying that account's effective permissions.
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
    this.pseudonymId,
    this.alias,
  });

  /// The account's id, null for a group. In an anonymous channel (#2949),
  /// a caller who is neither an admin nor a holder of `manage_members` gets
  /// [pseudonymId] here instead.
  final int? userId;

  /// The group's id, null for an account.
  final int? groupId;

  /// The username or group name; the [alias] to a caller who only sees
  /// pseudonyms.
  final String name;

  /// The account's pseudonym in an anonymous channel (#2949): the id its
  /// messages, reactions and events carry there. Null for a group and in any
  /// other channel.
  final int? pseudonymId;

  /// The name the account goes by in an anonymous channel, null elsewhere.
  final String? alias;

  /// Whether this row is account [id], by account id or pseudonym. A
  /// pseudonym is negative, so the two never collide.
  bool isAccount(int? id) => id != null && (userId == id || pseudonymId == id);

  /// The name this row is shown and mentioned by: its [alias] in an
  /// anonymous channel, [name] elsewhere.
  String get shownName => alias ?? name;

  /// The username behind [alias], for a caller who sees the real account in
  /// an anonymous channel; null for anyone else and elsewhere.
  String? get accountName =>
      pseudonymId != null && userId != pseudonymId ? name : null;

  /// Every account this row reaches, alone or as a group's.
  List<ChatMemberUser> get accounts => userId != null
      ? [
          ChatMemberUser(
            id: userId!,
            username: name,
            avatarUpdatedAt: avatarUpdatedAt,
            pseudonymId: pseudonymId,
            alias: alias,
          ),
        ]
      : users;

  /// Whether this is the Quark's own `everyone` group.
  final bool builtin;

  /// What this row lets its account or group do.
  final Set<ChatPermission> permissions;

  /// The account's profile picture version, null without one.
  final int? avatarUpdatedAt;

  /// A group's accounts; empty for an account, and for every group to a
  /// caller who only sees pseudonyms, whose account rows list them instead.
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
    pseudonymId: (json['pseudonymId'] as num?)?.toInt(),
    alias: json['alias'] as String?,
  );
}

/// What a channel's member rows say about its accounts. In an anonymous
/// channel (#2949) accounts are named by alias and carry their pseudonym,
/// which is what messages and events there name. A caller who only sees
/// pseudonyms gets every account as a row of its own and no
/// [ChatMember.users], so each person counts once, by their effective
/// permissions.
extension ChatMemberNames on List<ChatMember> {
  /// The names an `@mention` in the channel resolves to (#2623): every
  /// account that reads it, alone or through a group, in alphabetical order.
  /// A mention is only the text `@name` inside the encrypted message, so
  /// this list is all that decides what counts as one. Aliases in an
  /// anonymous channel.
  List<String> get mentionNames => {
    for (final m in this)
      if (m.permissions.contains(ChatPermission.readMessages))
        for (final u in m.accounts) u.shownName,
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// The accounts holding [permission] on the channel, through their own
  /// row or a group's, such as the authors whose `@everyone` counts (#4293),
  /// by the id messages carry: the pseudonym in an anonymous channel.
  Set<int> userIdsHolding(ChatPermission permission) => {
    for (final m in this)
      if (m.permissions.contains(permission))
        for (final u in m.accounts) u.pseudonymId ?? u.id,
  };

  /// The account [userId] names, by account id or pseudonym, or null when
  /// it is not among the members.
  ChatMemberUser? accountOf(int? userId) {
    for (final m in this) {
      for (final u in m.accounts) {
        if (u.isAccount(userId)) return u;
      }
    }
    return null;
  }

  /// Account [userId]'s name as it is in [mentionNames], or null when it is
  /// not among the members.
  String? nameOfUser(int? userId) => accountOf(userId)?.shownName;

  /// The id a channel event names account [userId] by: its pseudonym in an
  /// anonymous channel, the id itself elsewhere or when it isn't listed.
  int boundIdOf(int userId) => accountOf(userId)?.pseudonymId ?? userId;
}

/// An account listed under a group in [ChatMember.users].
class ChatMemberUser {
  /// Builds one explicitly; tests use it.
  const ChatMemberUser({
    required this.id,
    required this.username,
    this.avatarUpdatedAt,
    this.pseudonymId,
    this.alias,
  });

  /// The account's id; its [pseudonymId] to a caller who only sees
  /// pseudonyms in an anonymous channel (#2949).
  final int id;

  /// The account's username; its [alias] to that caller.
  final String username;

  /// The account's profile picture version, null without one.
  final int? avatarUpdatedAt;

  /// As [ChatMember.pseudonymId].
  final int? pseudonymId;

  /// As [ChatMember.alias].
  final String? alias;

  /// As [ChatMember.isAccount].
  bool isAccount(int? id) => id != null && (this.id == id || pseudonymId == id);

  /// As [ChatMember.shownName].
  String get shownName => alias ?? username;

  /// As [ChatMember.accountName].
  String? get accountName =>
      pseudonymId != null && id != pseudonymId ? username : null;

  /// Reads one.
  factory ChatMemberUser.fromJson(Map<String, dynamic> json) => ChatMemberUser(
    id: (json['id'] as num).toInt(),
    username: json['username'] as String? ?? '',
    avatarUpdatedAt: (json['avatarUpdatedAt'] as num?)?.toInt(),
    pseudonymId: (json['pseudonymId'] as num?)?.toInt(),
    alias: json['alias'] as String?,
  );
}
