import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

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

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final name = user.username;

    final actions = <(String, String, VoidCallback)>[
      if (!isSelf &&
          !user.isAdmin &&
          user.status == UserAccountStatus.active &&
          onPromote != null)
        ('promote', 'Make admin', onPromote!),
      if (!isSelf && user.isAdmin && onDemote != null)
        ('demote', 'Remove admin', onDemote!),
    ];

    final details = [
      if (isSelf) 'You',
      if (user.isAdmin) 'Admin',
      if (user.status == UserAccountStatus.disabled) 'Turned off',
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
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
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
                    child: Text(label),
                  ),
              ],
            ),
    );
  }
}
