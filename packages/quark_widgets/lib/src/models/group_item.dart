import 'package:flutter/foundation.dart';

import 'principal_item.dart';

/// One group as the group widgets need it: its id, its name, whether the
/// Quark defines it, and who is in it.
///
/// The package's own view of a group, so no widget imports the app's model.
/// Callbacks come back out with the [id].
@immutable
class GroupItem {
  /// Creates a group value.
  const GroupItem({
    required this.id,
    required this.name,
    this.isBuiltin = false,
    this.members = const [],
  });

  /// The group's id on the Quark, and what callbacks carry.
  final int id;

  /// The group's name, unique on the Quark ignoring case.
  final String name;

  /// Whether the Quark defines this group, such as `everyone`. It includes
  /// every account, so it has no [members] of its own and cannot be renamed
  /// or deleted.
  final bool isBuiltin;

  /// The accounts in the group, in the order they are shown. Always empty for
  /// a built-in group.
  final List<PrincipalItem> members;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupItem &&
          other.id == id &&
          other.name == name &&
          other.isBuiltin == isBuiltin &&
          listEquals(other.members, members);

  @override
  int get hashCode => Object.hash(id, name, isBuiltin, Object.hashAll(members));
}
