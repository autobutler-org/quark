import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/change_password/change_password_field.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The dialog body for changing the signed-in account's password (#3022):
/// the current password, and the new one twice.
///
/// Data in, callbacks out: it neither changes anything nor closes itself.
/// [onSubmit] fires with the current and the new password once the new one
/// is long enough, differs from the current one and was typed the same
/// twice; the caller runs the change, feeds [isWorking] and [error] back in,
/// and pops the dialog when it is done. The Quark checks the current
/// password; this only refuses to send an empty one.
///
/// Key prefixes: `change_password_current_field`,
/// `change_password_current_visibility`, `change_password_new_field`,
/// `change_password_new_visibility`, `change_password_confirm_field`,
/// `change_password_confirm_visibility`, `change_password_error`,
/// `change_password_cancel`, and `change_password_submit`.
///
/// ```dart
/// QuarkWidget.showDialog<bool>(
///   context,
///   builder: (ctx) => ListenableBuilder(
///     listenable: controller,
///     builder: (ctx, _) => ChangePasswordDialog(
///       isWorking: controller.isWorking,
///       error: controller.error,
///       onSubmit: (current, next) => change(ctx, current, next),
///       onCancel: () => Navigator.of(ctx).pop(),
///     ),
///   ),
/// );
/// ```
class ChangePasswordDialog extends StatefulWidget {
  /// Creates the dialog body.
  const ChangePasswordDialog({
    required this.onSubmit,
    required this.onCancel,
    this.isWorking = false,
    this.error,
    super.key,
  });

  /// Called with the current password and the new one, once both pass the
  /// dialog's own checks.
  final void Function(String currentPassword, String newPassword) onSubmit;

  /// Called when the user backs out through the cancel button.
  final VoidCallback onCancel;

  /// Whether the change is in flight: the fields and buttons are disabled
  /// and the submit button shows a loader.
  final bool isWorking;

  /// Why the last attempt failed, from `Errors`, or null.
  final String? error;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// What is wrong with the new password as typed so far, or null. Says
  /// nothing about a field that is still empty.
  String? get _problem {
    final next = _newController.text;
    final confirm = _confirmController.text;
    if (next.isEmpty) return null;
    if (next.length < Errors.minPasswordLength) return Errors.passwordTooShort;
    if (next == _currentController.text) return Errors.passwordUnchanged;
    if (confirm.isNotEmpty && confirm != next) return Errors.passwordsDontMatch;
    return null;
  }

  bool get _canSubmit =>
      !widget.isWorking &&
      _currentController.text.isNotEmpty &&
      _confirmController.text.isNotEmpty &&
      _problem == null;

  void _submit() {
    if (!_canSubmit) return;
    widget.onSubmit(_currentController.text, _newController.text);
  }

  void _changed(String _) => setState(() {});

  void _submitted(String _) => _submit();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // What was typed is checked first: the last attempt's failure is stale
    // once the fields no longer hold what was sent.
    final error = _problem ?? widget.error;

    return QuarkWidget.alertDialog(
      title: const Text('Change password'),
      scrollable: true,
      content: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your current password, then choose a new one. You stay '
              'signed in on this device.',
            ),
            const SizedBox(height: 16),
            ChangePasswordField(
              keyPrefix: 'change_password_current',
              label: 'Current password',
              controller: _currentController,
              autofillHints: const [AutofillHints.password],
              enabled: !widget.isWorking,
              autofocus: true,
              onChanged: _changed,
              onSubmitted: _submitted,
            ),
            const SizedBox(height: 12),
            ChangePasswordField(
              keyPrefix: 'change_password_new',
              label: 'New password',
              controller: _newController,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !widget.isWorking,
              onChanged: _changed,
              onSubmitted: _submitted,
            ),
            const SizedBox(height: 12),
            ChangePasswordField(
              keyPrefix: 'change_password_confirm',
              label: 'Confirm new password',
              controller: _confirmController,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !widget.isWorking,
              onChanged: _changed,
              onSubmitted: _submitted,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error,
                key: const ValueKey('change_password_error'),
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Tooltip(
          message: 'Keep your current password',
          child: TextButton(
            key: const ValueKey('change_password_cancel'),
            onPressed: widget.isWorking ? null : widget.onCancel,
            child: const Text('Cancel'),
          ),
        ),
        Tooltip(
          message: 'Change your password',
          child: FilledButton(
            key: const ValueKey('change_password_submit'),
            onPressed: _canSubmit ? _submit : null,
            child: widget.isWorking
                ? const QuarkLoader(size: 20)
                : const Text('Change password'),
          ),
        ),
      ],
    );
  }
}
