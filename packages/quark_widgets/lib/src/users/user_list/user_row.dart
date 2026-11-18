import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_menu_row.dart';
import '../../models/user_account_item.dart';
import '../../models/quark_menu_entry.dart';

/// One account in a [UserList]: its name, what it is (including a recovery
/// phrase too short to keep), and a menu of the actions on offer.
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
    this.onMessage,
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

  /// Messages the account in chat. Offered on active accounts; null leaves
  /// it out.
  final VoidCallback? onMessage;

  /// Makes the account an admin. Offered on active accounts that are not
  /// admins; null leaves it out.
  final VoidCallback? onPromote;

  /// Stops the account being an admin. Offered on admins; null leaves it out.
  final VoidCallback? onDemote;

  /// Disables the account. Offered on active accounts; null leaves it out.
  final VoidCallback? onDisable;

  /// Enables the account again. Offered on disabled accounts; null leaves
  /// it out.
  final VoidCallback? onEnable;

  /// Deletes the account. Offered on any account; null leaves it out.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final name = user.username;
    final isActive = user.status == UserAccountStatus.active;
    final isDisabled = user.status == UserAccountStatus.disabled;

    final actions = isSelf
        ? const <(String, String, VoidCallback)>[]
        : <(String, String, VoidCallback)>[
            if (isActive && onMessage != null)
              ('message', 'Message', onMessage!),
            if (!user.isAdmin && isActive && onPromote != null)
              ('promote', 'Make admin', onPromote!),
            if (user.isAdmin && onDemote != null)
              ('demote', 'Remove admin', onDemote!),
            if (isActive && onDisable != null)
              ('disable', 'Disable', onDisable!),
            if (isDisabled && onEnable != null) ('enable', 'Enable', onEnable!),
            if (onDelete != null) ('delete', 'Delete', onDelete!),
          ];

    final details = [
      if (isSelf) 'You',
      if (user.isAdmin) 'Admin',
      if (isDisabled) 'Disabled',
      if (user.status == UserAccountStatus.pending) 'Waiting for approval',
      if (user.shortRecoveryPhrase) 'Short recovery phrase',
    ];

    final entries = [
      for (final (id, label, action) in actions)
        QuarkMenuEntry(
          key: ValueKey('user_action_${id}_$name'),
          label: label,
          destructive: id == 'delete',
          onSelected: action,
        ),
    ];
    return QuarkMenuRow(
      key: ValueKey('user_row_$name'),
      menuKey: ValueKey('user_menu_$name'),
      leading: Icon(
        user.isAdmin ? QuarkIcons.shield_outlined : QuarkIcons.person_outline,
      ),
      title: name,
      subtitle: details.isEmpty ? null : details.join(' · '),
      busy: isBusy,
      menuTooltip: 'Actions for $name',
      entries: entries,
    );
  }
}
