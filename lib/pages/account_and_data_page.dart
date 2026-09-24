import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/account_actions_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/delete_account_dialog.dart';
import 'package:quark/widgets/settings/reset_quark_dialog.dart';
import 'package:quark_icons/quark_icons.dart';

/// The drill-down behind Settings' **Account and data** row (#2346): deleting
/// the account, and for admins, resetting this Quark.
///
/// Both used to sit on Settings itself, one card under Sign out, where a
/// mis-tap on a phone opened the deletion flow. Here they are one labeled tap
/// away — still easy to find, as App Store Review Guideline 5.1.1(v) requires
/// of account deletion (#1762), but not next to anything a person taps often.
///
/// The two intents stay apart: **Delete account** for everyone, then a
/// separate **Reset** section for admins only (#1899). Each asks for the
/// account's password before anything is sent.
///
/// Key prefixes: `account_and_data_page`, `settings_delete_account`, and
/// `settings_reset_quark`.
class AccountAndDataPage extends StatefulWidget {
  /// Creates the page.
  const AccountAndDataPage({super.key});

  @override
  State<AccountAndDataPage> createState() => _AccountAndDataPageState();
}

class _AccountAndDataPageState extends State<AccountAndDataPage> {
  /// Owns the account actions' service calls, so this [State] does not.
  final _accountActions = AccountActionsController();

  @override
  void dispose() {
    _accountActions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Scaffold(
      key: const ValueKey('account_and_data_page'),
      appBar: AppBar(title: const Text('Account and data')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            _accountActions,
            AppSettings.instance.isAdmin,
          ]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Account',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  key: const ValueKey('settings_delete_account'),
                  leading: Icon(
                    QuarkIcons.delete_forever_outlined,
                    color: error,
                  ),
                  title: Text('Delete account', style: TextStyle(color: error)),
                  subtitle: const Text(
                    'Permanently deletes your account on this Quark',
                  ),
                  onTap: _accountActions.isWorking ? null : _deleteAccount,
                ),
              ),
              // The other intent, kept a section away from the first.
              // Resetting the appliance is not an account action and must
              // never read like one, so it gets its own heading and its own
              // words rather than a checkbox on the deletion dialog (#1762).
              // Only an admin may reset the appliance (#1899).
              if (AppSettings.instance.isAdmin.value) ...[
                const SizedBox(height: 24),
                const Text(
                  'Reset',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    key: const ValueKey('settings_reset_quark'),
                    leading: Icon(Icons.restart_alt, color: error),
                    title: Text(
                      'Reset this Quark',
                      style: TextStyle(color: error),
                    ),
                    // Says what the dialog will ask rather than promising the
                    // widest possible wipe: attached drives are left alone
                    // unless the user asks for them (#2052).
                    subtitle: const Text(
                      'Returns this Quark to first-boot setup. You choose what '
                      'it erases; attached drives are left alone unless you '
                      'say otherwise',
                    ),
                    onTap: _accountActions.isWorking ? null : _resetQuark,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Confirms deleting the account, then routes out.
  ///
  /// The controller does the deleting; the dialog and the navigation stay
  /// here, where a page's do.
  Future<void> _deleteAccount() async {
    final password = await QuarkWidget.showDialog<String>(
      context,
      builder: (ctx) => DeleteAccountDialog(
        username: _accountActions.username,
        onConfirm: (typed) => Navigator.of(ctx).pop(typed),
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
    if (password == null || !mounted) return;

    await _leaveAfter(
      () => _accountActions.deleteAccount(password: password),
      'Your account is gone.',
    );
  }

  /// Confirms a factory reset, then routes out.
  ///
  /// A separate entry, separate copy and separate call from [_deleteAccount]:
  /// nothing that starts as "delete my account" can end as a wiped appliance.
  Future<void> _resetQuark() async {
    final confirmation =
        await QuarkWidget.showDialog<(QuarkResetSelection, String)>(
          context,
          builder: (ctx) => ResetQuarkDialog(
            onConfirm: (selection, password) =>
                Navigator.of(ctx).pop((selection, password)),
            onCancel: () => Navigator.of(ctx).pop(),
          ),
        );
    if (confirmation == null || !mounted) return;

    await _leaveAfter(
      () => _accountActions.resetQuark(
        selection: confirmation.$1,
        password: confirmation.$2,
      ),
      'This Quark has been reset.',
    );
  }

  /// Runs [action], then either reports why it failed or leaves the app for
  /// wherever a signed-out user belongs.
  ///
  /// [done] is what the user is told on the way out. The Quark reports whether
  /// files survived, so the notice about them is the truth after the fact
  /// rather than a second guess at what was asked for. The snack bar is shown
  /// before navigating on purpose: the root [ScaffoldMessenger] outlives this
  /// route, so the message survives the trip to setup or login.
  Future<void> _leaveAfter(
    Future<String?> Function() action,
    String done,
  ) async {
    final destination = await action();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (destination == null) {
      messenger.showSnackBar(SnackBar(content: Text(_accountActions.error!)));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _accountActions.filesRetained
              ? '$done Your files are still on this Quark.'
              : done,
        ),
      ),
    );
    // The token is already gone, so the router's gate would move the user on
    // regardless. Going straight there means they never watch this page fail
    // to load against a Quark they can no longer sign in to.
    context.go(destination);
  }
}
