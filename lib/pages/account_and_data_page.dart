import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/controllers/account_actions_controller.dart';
import 'package:quark/utils/leave_after_account_action.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/delete_account_dialog.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The drill-down behind Settings' **Account and data** row (#2346): deleting
/// the account.
///
/// Both used to sit on Settings itself, one card under Sign out, where a
/// mis-tap on a phone opened the deletion flow. Here they are one labeled tap
/// away — still easy to find, as App Store Review Guideline 5.1.1(v) requires
/// of account deletion (#1762), but not next to anything a person taps often.
///
/// Resetting this Quark used to sit here too, a section below. It wipes the
/// household's whole device, not one account, so it moved to Settings ›
/// Updates' Maintenance group (#4151). Deleting asks for the account's
/// password before anything is sent.
///
/// Key prefixes: `account_and_data_page` and `settings_delete_account`.
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
    return Scaffold(
      key: const ValueKey('account_and_data_page'),
      appBar: ChromeAppBar(title: const Text('Account and data')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _accountActions,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              QuarkSection(
                title: 'Account',
                child: SettingsRow(
                  key: const ValueKey('settings_delete_account'),
                  destructive: true,
                  leading: const Icon(QuarkIcons.delete_forever_outlined),
                  title: const Text('Delete account'),
                  // Names what it leaves alone, so it cannot be read as the
                  // wider reset (#2479).
                  subtitle: const Text(
                    'Removes only your account, permanently. Your files and '
                    'other accounts stay on this Quark',
                  ),
                  onTap: _accountActions.isWorking ? null : _deleteAccount,
                ),
              ),
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

    await leaveAfterAccountAction(
      context,
      _accountActions,
      () => _accountActions.deleteAccount(password: password),
      'Your account is gone.',
    );
  }
}
