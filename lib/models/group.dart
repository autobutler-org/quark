/// One group on the Quark, as `GET /api/v0/admin/groups` lists it (#1910).
class Group {
  const Group({
    required this.id,
    required this.name,
    this.builtin = false,
    this.members = const [],
  });

  final int id;
  final String name;

  /// Whether the Quark defines the group, like `everyone`: every account is
  /// in it, so it has no member rows and cannot be renamed or deleted.
  final bool builtin;

  /// The accounts in the group. Always empty for a [builtin] group.
  final List<GroupMember> members;

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    builtin: json['builtin'] as bool? ?? false,
    members: (json['members'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GroupMember.fromJson)
        .toList(growable: false),
  );
}

/// One account in a [Group].
class GroupMember {
  const GroupMember({required this.id, required this.username});

  final int id;
  final String username;

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
  );
}
