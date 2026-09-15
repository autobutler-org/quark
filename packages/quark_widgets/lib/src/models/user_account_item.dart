import 'package:flutter/foundation.dart';

/// Where an account stands on the Quark.
enum UserAccountStatus {
  /// Someone asked for the account and no admin has approved it yet.
  pending,

  /// The account can sign in.
  active,

  /// An admin turned the account off. It keeps its files but cannot sign in.
  disabled,
}

/// One account as the user widgets need it: a name, whether it is an admin,
/// and its status.
///
/// The package's own view of an account, so no widget imports the app's
/// model. Controllers map their account type into this at the edge, and
/// callbacks come back out with the [username].
@immutable
class UserAccountItem {
  /// Creates an account row value.
  const UserAccountItem({
    required this.username,
    this.isAdmin = false,
    this.status = UserAccountStatus.active,
  });

  /// The account's username, unique on the Quark, and what callbacks carry.
  final String username;

  /// Whether the account is an admin.
  final bool isAdmin;

  /// Whether the account is waiting for approval, active, or turned off.
  final UserAccountStatus status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAccountItem &&
          other.username == username &&
          other.isAdmin == isAdmin &&
          other.status == status;

  @override
  int get hashCode => Object.hash(username, isAdmin, status);
}
