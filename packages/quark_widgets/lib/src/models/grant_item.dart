import 'package:flutter/foundation.dart';

import 'access_level.dart';
import 'principal_item.dart';

/// One account or group with access to a file or folder, as the share sheet
/// shows it.
///
/// Access is set on the item itself, or inherited from a folder the item is
/// in. Access adds up down the tree, so a folder's access reaches everything
/// inside it and can only be changed on that folder.
@immutable
class GrantItem {
  /// Creates a grant value.
  const GrantItem({
    required this.principal,
    required this.level,
    this.inheritedFrom,
  });

  /// Who has the access.
  final PrincipalItem principal;

  /// How much they may do.
  final AccessLevel level;

  /// The name of the folder the access is set on when it is inherited, such
  /// as `Family`. Null for access set on the item itself.
  final String? inheritedFrom;

  /// Whether the access is set on a folder the item is in rather than on the
  /// item.
  bool get isInherited => inheritedFrom != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GrantItem &&
          other.principal == principal &&
          other.level == level &&
          other.inheritedFrom == inheritedFrom;

  @override
  int get hashCode => Object.hash(principal, level, inheritedFrom);
}
