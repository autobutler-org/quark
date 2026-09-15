import 'package:flutter/foundation.dart';

/// Whether a [PrincipalItem] is one account or a group of them.
enum PrincipalKind {
  /// One account.
  user,

  /// A group of accounts.
  group,
}

/// An account or a group, as the widgets that pick one or list who has
/// access need it: what it is, its id, and its name.
///
/// The package's own view, so no widget imports the app's models. Ids are
/// only unique within a kind, so [keySuffix] carries both.
@immutable
class PrincipalItem {
  /// Creates a principal value.
  const PrincipalItem({
    required this.kind,
    required this.id,
    required this.name,
    this.isBuiltin = false,
  });

  /// Whether this is an account or a group.
  final PrincipalKind kind;

  /// The id the Quark gave it, unique among principals of the same [kind].
  final int id;

  /// The username of an account, or the name of a group.
  final String name;

  /// Whether this is a group the Quark defines, such as `everyone`, whose
  /// members are every account and cannot be changed.
  final bool isBuiltin;

  /// `<kind>_<id>`, such as `user_3` or `group_1`: unique across accounts and
  /// groups, and the end of every key a widget builds for this principal.
  String get keySuffix => '${kind.name}_$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrincipalItem &&
          other.kind == kind &&
          other.id == id &&
          other.name == name &&
          other.isBuiltin == isBuiltin;

  @override
  int get hashCode => Object.hash(kind, id, name, isBuiltin);
}
