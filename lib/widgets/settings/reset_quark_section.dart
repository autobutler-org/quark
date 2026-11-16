import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/account_actions_controller.dart';
import 'package:quark/utils/leave_after_account_action.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/reset_quark_dialog.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The admin's **Reset this Quark** entry, in a danger-tinted box at the end
/// of Settings › Updates' Maintenance group (#4151).
///
/// It sat on Account and data beside Delete account, which told an admin the
/// wrong blast radius: deleting removes one account, resetting wipes the
/// household's whole device. The entry, its copy and [ResetQuarkDialog] are
/// unchanged; only where it lives moved. The caller shows it to admins only
/// (#1899).
///
/// Owns an [AccountActionsController] unless [controller] is given. Asks for
/// the password in the dialog, then signs out to setup or login.
///
/// Key prefixes: `settings_reset_quark` on the entry, `reset_quark_box` on
/// the tinted box.
class ResetQuarkSection extends StatefulWidget {
  /// Creates the section, with the real services unless [controller] is
  /// given.
  const ResetQuarkSection({this.controller, super.key});

  /// Injected for tests. Created and disposed here when null.
  final AccountActionsController? controller;

  @override
  State<ResetQuarkSection> createState() => _ResetQuarkSectionState();
}

class _ResetQuarkSectionState extends State<ResetQuarkSection> {
  late final AccountActionsController _controller =
      widget.controller ?? AccountActionsController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// Confirms a factory reset, then routes out.
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

    await leaveAfterAccountAction(
      context,
      _controller,
      () => _controller.resetQuark(
        selection: confirmation.$1,
        password: confirmation.$2,
      ),
      'This Quark has been reset.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => DecoratedBox(
        key: const ValueKey('reset_quark_box'),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.08),
          border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: SettingsRow(
          key: const ValueKey('settings_reset_quark'),
          destructive: true,
          leading: const Icon(QuarkIcons.restart),
          title: const Text('Reset this Quark'),
          // Says what the dialog will ask rather than promising the widest
          // possible wipe: attached drives are left alone unless the user
          // asks for them (#2052), and the box that asks is named so they
          // know where to look (#2479).
          subtitle: const Text(
            'Erases every account, not just yours, and returns this Quark '
            'to first-boot setup. The next step lists what it erases; '
            'attached drives are left alone unless you check '
            '“$kResetQuarkDevicesLabel” there',
          ),
          onTap: _controller.isWorking ? null : _resetQuark,
        ),
      ),
    );
  }
}
