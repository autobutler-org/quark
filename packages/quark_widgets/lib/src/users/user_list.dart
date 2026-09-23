import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/user_account_item.dart';
import '../theme/quark_tokens.dart';
import 'user_list/user_row.dart';

/// The accounts on a Quark, one row each, with the actions an admin can take
/// on an account in a menu at the end of its row.
///
/// Loading, the error and the empty list are the caller's to decide, and each
/// renders on its own. The list lays out as a column rather than scrolling
/// itself, so it sits in a page's own scroll view with the sections around it.
///
/// The signed-in account's row, [selfUsername], never offers actions: an admin
/// changes their own account from Settings. An action whose callback is null
/// is left out of every menu, and a row whose menu would be empty has none.
///
/// Key prefixes: `user_row_<username>` on each row, `user_menu_<username>` on
/// its menu button, and `user_action_<action>_<username>` on the menu
/// entries, where the action is `promote`, `demote`, `disable`, `enable` or
/// `delete`.
///
/// ```dart
/// UserList(
///   users: controller.accounts,
///   selfUsername: controller.selfUsername,
///   isLoading: controller.isLoading,
///   error: loadError,
///   busyUsernames: controller.busyUsernames,
///   onPromote: promote,
///   onDemote: demote,
///   onDisable: disable,
///   onEnable: enable,
///   onDelete: confirmDelete,
/// );
/// ```
class UserList extends StatelessWidget {
  /// Creates the list of [users].
  const UserList({
    required this.users,
    this.selfUsername,
    this.isLoading = false,
    this.error,
    this.busyUsernames = const {},
    this.onPromote,
    this.onDemote,
    this.onDisable,
    this.onEnable,
    this.onDelete,
    super.key,
  });

  /// The accounts to list, in the order they are shown.
  final List<UserAccountItem> users;

  /// The signed-in account, whose row offers no actions. Null when unknown.
  final String? selfUsername;

  /// Whether the accounts are still loading. Shows a spinner in place of the
  /// rows.
  final bool isLoading;

  /// A sentence saying why the accounts could not be loaded, composed by the
  /// caller. Shown in place of the rows.
  final String? error;

  /// Accounts with an action in flight. Their rows show progress in place of
  /// the menu.
  final Set<String> busyUsernames;

  /// Called with the username to make an admin. Offered on active accounts
  /// that are not admins. Null leaves the entry out.
  final ValueChanged<String>? onPromote;

  /// Called with the username to stop being an admin. Offered on admins. Null
  /// leaves the entry out.
  final ValueChanged<String>? onDemote;

  /// Called with the username to turn off. Offered on active accounts. Null
  /// leaves the entry out.
  final ValueChanged<String>? onDisable;

  /// Called with the username to turn back on. Offered on turned-off
  /// accounts. Null leaves the entry out.
  final ValueChanged<String>? onEnable;

  /// Called with the username to delete. Offered on every account but your
  /// own; the caller confirms before deleting. Null leaves the entry out.
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: const Center(child: QuarkLoader()),
      );
    }
    if (error != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacingMd),
        child: Text(error, style: TextStyle(color: tokens.error)),
      );
    }
    if (users.isEmpty) {
      return const EmptyStateWidget(
        icon: QuarkIcons.person_outline,
        headline: 'No accounts yet',
      );
    }

    VoidCallback? bind(ValueChanged<String>? callback, String username) =>
        callback == null ? null : () => callback(username);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final user in users)
          UserRow(
            user: user,
            isSelf: user.username == selfUsername,
            isBusy: busyUsernames.contains(user.username),
            onPromote: bind(onPromote, user.username),
            onDemote: bind(onDemote, user.username),
            onDisable: bind(onDisable, user.username),
            onEnable: bind(onEnable, user.username),
            onDelete: bind(onDelete, user.username),
          ),
      ],
    );
  }
}
