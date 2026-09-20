/// Who has access to one file or folder, and whether the signed-in account
/// may change that, as `/api/v0/access` answers (#1911).
class PathAccess {
  const PathAccess({
    required this.deviceSerial,
    required this.relPath,
    this.canManage = false,
    this.canGrantOwner = false,
    this.grants = const [],
  });

  final String deviceSerial;

  /// The path in the Quark's own spelling, which each [PathGrant.from] is
  /// compared with.
  final String relPath;

  /// Whether the signed-in account may change who has access.
  final bool canManage;

  /// Whether it may give the owner level. The Quark keeps this equal to
  /// [canManage]: owners can make other owners.
  final bool canGrantOwner;

  /// Access set on the path first, then access inherited from the folders it
  /// is in, one row per account or group at its highest level.
  final List<PathGrant> grants;

  factory PathAccess.fromJson(Map<String, dynamic> json) => PathAccess(
    deviceSerial: json['deviceSerial'] as String? ?? '',
    relPath: json['relPath'] as String? ?? '',
    canManage: json['canManage'] as bool? ?? false,
    canGrantOwner: json['canGrantOwner'] as bool? ?? false,
    grants: (json['grants'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PathGrant.fromJson)
        .toList(growable: false),
  );
}

/// One account or group with access to a path.
class PathGrant {
  const PathGrant({
    this.userId,
    this.groupId,
    required this.name,
    this.builtin = false,
    required this.level,
    required this.from,
  });

  /// The account's id, or null for a group.
  final int? userId;

  /// The group's id, or null for an account.
  final int? groupId;

  /// The account's username or the group's name.
  final String name;

  /// Whether this is a group the Quark defines, such as `everyone`.
  final bool builtin;

  /// `read`, `write` or `owner`.
  final String level;

  /// The path the access is set on: the path itself, or a folder it is in.
  final String from;

  factory PathGrant.fromJson(Map<String, dynamic> json) => PathGrant(
    userId: (json['userId'] as num?)?.toInt(),
    groupId: (json['groupId'] as num?)?.toInt(),
    name: json['name'] as String? ?? '',
    builtin: json['builtin'] as bool? ?? false,
    level: json['level'] as String? ?? 'read',
    from: json['from'] as String? ?? '',
  );
}

/// Every account and group a path can be shared with, as
/// `GET /api/v0/access/principals` lists them.
class SharePrincipals {
  const SharePrincipals({this.users = const [], this.groups = const []});

  /// Accounts that can sign in, by username.
  final List<({int id, String username})> users;

  /// Groups, `everyone` first.
  final List<({int id, String name, bool builtin})> groups;

  factory SharePrincipals.fromJson(Map<String, dynamic> json) =>
      SharePrincipals(
        users: [
          for (final user
              in (json['users'] as List? ?? const [])
                  .whereType<Map<String, dynamic>>())
            (
              id: (user['id'] as num?)?.toInt() ?? 0,
              username: user['username'] as String? ?? '',
            ),
        ],
        groups: [
          for (final group
              in (json['groups'] as List? ?? const [])
                  .whereType<Map<String, dynamic>>())
            (
              id: (group['id'] as num?)?.toInt() ?? 0,
              name: group['name'] as String? ?? '',
              builtin: group['builtin'] as bool? ?? false,
            ),
        ],
      );
}

/// The root of one ad-hoc share, as `GET /api/v0/access/mine` lists them
/// (#2139).
///
/// The Quark leaves out everything the file browser already reaches another
/// way — the account's own home, the folders of its groups, the scaffolding
/// holding both — so what comes back is what Shared with me offers and
/// nothing else.
class SharedRoot {
  const SharedRoot({
    required this.relPath,
    this.deviceSerial = '',
    this.level = 'read',
    this.owner = '',
  });

  /// The path in the Quark's own spelling.
  final String relPath;

  /// The drive it sits on, empty for the Quark's own.
  final String deviceSerial;

  /// `read`, `write` or `owner`.
  final String level;

  /// The account or group that owns it, empty when the Quark could name none.
  final String owner;

  /// The item's own name, without the folders holding it.
  String get name {
    final trimmed = relPath.replaceFirst(RegExp(r'/+$'), '');
    final lastSlash = trimmed.lastIndexOf('/');
    return lastSlash < 0 ? trimmed : trimmed.substring(lastSlash + 1);
  }

  factory SharedRoot.fromJson(Map<String, dynamic> json) => SharedRoot(
    relPath: json['relPath'] as String? ?? '',
    deviceSerial: json['deviceSerial'] as String? ?? '',
    level: json['level'] as String? ?? 'read',
    owner: json['owner'] as String? ?? '',
  );
}
