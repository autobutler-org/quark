import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_loader.dart';
import '../../models/user_account_item.dart';
import '../../theme/quark_tokens.dart';

/// One account in a [UserList]: its name, what it is, and a menu of the
/// actions on offer.
///
/// A part of [UserList], tested through it.
///
/// Key prefixes: `user_row_<username>`, `user_menu_<username>`, and
/// `user_action_<action>_<username>` on each menu entry.
class UserRow extends StatelessWidget {
  /// Creates the row for [user].
  const UserRow({
    required this.user,
    this.isSelf = false,
    this.isBusy = false,
    this.onPromote,
    this.onDemote,
    this.onDisable,
    this.onEnable,
    this.onDelete,
    super.key,
  });

  /// The account this row shows.
  final UserAccountItem user;

  /// Whether this is the signed-in account, which offers no actions.
  final bool isSelf;

  /// Whether an action on this account is in flight.
  final bool isBusy;

  /// Makes the account an admin. Offered on active accounts that are not
  /// admins; null leaves it out.
  final VoidCallback? onPromote;

  /// Stops the account being an admin. Offered on admins; null leaves it out.
  final VoidCallback? onDemote;

  /// Turns the account off. Offered on active accounts; null leaves it out.
  final VoidCallback? onDisable;

  /// Turns the account back on. Offered on turned-off accounts; null leaves
  /// it out.
  final VoidCallback? onEnable;

  /// Deletes the account. Offered on any account; null leaves it out.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final name = user.username;
    final isActive = user.status == UserAccountStatus.active;
    final isDisabled = user.status == UserAccountStatus.disabled;

    final actions = isSelf
        ? const <(String, String, VoidCallback)>[]
        : <(String, String, VoidCallback)>[
            if (!user.isAdmin && isActive && onPromote != null)
              ('promote', 'Make admin', onPromote!),
            if (user.isAdmin && onDemote != null)
              ('demote', 'Remove admin', onDemote!),
            if (isActive && onDisable != null)
              ('disable', 'Turn off', onDisable!),
            if (isDisabled && onEnable != null)
              ('enable', 'Turn on', onEnable!),
            if (onDelete != null) ('delete', 'Delete', onDelete!),
          ];

    final details = [
      if (isSelf) 'You',
      if (user.isAdmin) 'Admin',
      if (isDisabled) 'Turned off',
      if (user.status == UserAccountStatus.pending) 'Waiting for approval',
    ];

    return ListTile(
      key: ValueKey('user_row_$name'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        user.isAdmin ? QuarkIcons.shield_outlined : QuarkIcons.person_outline,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.mutedForeground),
            ),
      trailing: isBusy
          ? const QuarkLoader(size: 24)
          : actions.isEmpty
          ? null
          : PopupMenuButton<VoidCallback>(
              key: ValueKey('user_menu_$name'),
              tooltip: 'Actions for $name',
              icon: const Icon(QuarkIcons.more_vert),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                for (final (id, label, action) in actions)
                  PopupMenuItem(
                    key: ValueKey('user_action_${id}_$name'),
                    value: action,
                    child: Text(
                      label,
                      style: id == 'delete'
                          ? TextStyle(color: tokens.error)
                          : null,
                    ),
                  ),
              ],
            ),
    );
  }
}
