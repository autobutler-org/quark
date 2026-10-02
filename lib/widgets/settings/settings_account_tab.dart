import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// The Account tab of Settings (#2350): the [profile] card (#2419), sign
/// out, the [sessions] card (#1663), who manages accounts (#2474), with an
/// Account and data row at the bottom that leads to Delete account and, for an admin, Reset
/// this Quark (#2346).
///
/// Account deletion has to be initiated in the app and has to be findable,
/// per App Store Review Guideline 5.1.1(v) (#1762): a tab labeled Account is
/// where a reviewer looks, and a labeled row leading to the flow is the
/// accepted pattern. The row sits below Sign out, set apart from it, and
/// nothing destructive is on this tab itself.
///
/// Accounts and groups are an admin's to manage, so a member is told so
/// rather than left to wonder where account management went, and an admin
/// gets a row to the Users page where it happens (#2474).
///
/// Keys: `settings_account_users`, `settings_account_admin_note` and
/// `settings_account_and_data`.
class SettingsAccountTab extends StatelessWidget {
  /// Creates the tab.
  const SettingsAccountTab({
    required this.signedIn,
    required this.isAdmin,
    required this.onSignOut,
    required this.onOpenAccountAndData,
    required this.onOpenUsers,
    this.header,
    this.profile,
    this.sessions,
    super.key,
  });

  /// Whether there is a session to sign out of or an account to delete.
  final bool signedIn;

  /// Whether the Quark says this user is an admin, which adds Reset this
  /// Quark to what the Account and data row names (#1899), and swaps the
  /// note on who manages accounts for a row to Users.
  final bool isAdmin;

  /// Called when the user taps Sign out.
  final VoidCallback onSignOut;

  /// Called when the user taps Account and data.
  final VoidCallback onOpenAccountAndData;

  /// Called when an admin taps Users and groups.
  final VoidCallback onOpenUsers;

  /// Shown above the tab's content and scrolled with it, such as the
  /// page's disconnected banner; null shows nothing.
  final Widget? header;

  /// The Profile card, shown first while signed in; null shows nothing.
  final Widget? profile;

  /// The Sessions card, shown under Sign out; null shows nothing.
  final Widget? sessions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (header != null) ...[header!, const SizedBox(height: 24)],
        if (!signedIn)
          const Text('Not signed in')
        else ...[
          if (profile != null) ...[profile!, const SizedBox(height: 16)],
          Card(
            child: ListTile(
              leading: const Icon(QuarkIcons.logout),
              title: const Text('Sign out'),
              onTap: onSignOut,
            ),
          ),
          if (sessions != null) ...[const SizedBox(height: 16), sessions!],
          const SizedBox(height: 16),
          Card(
            child: isAdmin
                ? ListTile(
                    key: const ValueKey('settings_account_users'),
                    leading: const Icon(QuarkIcons.group_outlined),
                    title: const Text('Users and groups'),
                    subtitle: const Text(
                      'Add accounts, approve requests and manage groups',
                    ),
                    trailing: const Icon(QuarkIcons.chevron_right),
                    onTap: onOpenUsers,
                  )
                : const ListTile(
                    key: ValueKey('settings_account_admin_note'),
                    leading: Icon(QuarkIcons.info_outline),
                    title: Text('Accounts are managed by an admin'),
                    subtitle: Text(
                      'An admin of this Quark adds accounts and groups and '
                      'decides who else is an admin. Ask one for a new '
                      'account or a change to yours.',
                    ),
                  ),
          ),
          // Kept well clear of Sign out, so a mis-tap cannot reach it.
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              key: const ValueKey('settings_account_and_data'),
              leading: const Icon(QuarkIcons.person_outline),
              title: const Text('Account and data'),
              subtitle: Text(
                isAdmin
                    ? 'Delete your account or reset this Quark'
                    : 'Delete your account',
              ),
              trailing: const Icon(QuarkIcons.chevron_right),
              onTap: onOpenAccountAndData,
            ),
          ),
        ],
      ],
    );
  }
}
