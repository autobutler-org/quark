import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/confirm_password_field.dart';

/// What the user reads when their files will outlive their account.
///
/// A constant so the widget that shows it and the test that guards it cannot
/// drift apart, and so removing the copy has to happen somewhere visible.
const String kDeleteAccountFilesWarning =
    'Your files stay on this Quark. Whoever sets it up next will be able to '
    'open them. To erase them too, use Reset this Quark instead.';

/// The confirmation body for deleting the signed-in account (#1762).
///
/// Data in, callbacks out: it neither deletes anything nor closes itself.
/// [onConfirm] fires with the typed password, and the caller that pushed the
/// dialog is the one that pops it.
///
/// Deleting an account and factory-resetting an appliance are two intents, and
/// this dialog only has one of them. There is no control here that can reach
/// the appliance-wide aspects of the endpoint — those live behind Reset this
/// Quark, in their own words, on their own surface. Nobody can arrive here to
/// delete a login and leave having wiped a device.
///
/// The cost of that narrowness is the thing this dialog has to say out loud:
/// the file tree survives, the Quark returns to setup with it intact, and
/// whoever claims it next can read it. [kDeleteAccountFilesWarning] says so,
/// above the confirmation rather than under it.
///
/// The confirmation is the account's password (#2346), not its username:
/// anyone holding an unlocked phone can read the username off the screen. The
/// Quark checks it; this dialog only refuses to send an empty one.
///
/// Key prefixes: `delete_account_password_field`,
/// `delete_account_password_visibility`, `delete_account_files_warning`,
/// `delete_account_cancel`, and `delete_account_submit`.
///
/// ```dart
/// QuarkWidget.showDialog<String>(
///   context,
///   builder: (ctx) => DeleteAccountDialog(
///     username: AppSettings.instance.username,
///     onConfirm: (password) => Navigator.of(ctx).pop(password),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class DeleteAccountDialog extends StatefulWidget {
  /// Creates the confirmation body for [username]'s account.
  const DeleteAccountDialog({
    required this.onConfirm,
    required this.onCancel,
    this.username,
    super.key,
  });

  /// The account being deleted, or null when this session never named one.
  /// Only used to phrase the dialog.
  final String? username;

  /// Called with the typed password, once one has been typed.
  final ValueChanged<String> onConfirm;

  /// Called when the user backs out through the cancel button.
  final VoidCallback onCancel;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  bool get _hasPassword => _passwordController.text.isNotEmpty;

  void _submit() {
    if (!_hasPassword) return;
    widget.onConfirm(_passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final username = widget.username;

    return QuarkWidget.alertDialog(
      title: const Text('Delete account'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            username == null
                ? 'Your account will be deleted and you will be signed out '
                      'everywhere. This cannot be undone.'
                : 'The account $username will be deleted and you will be '
                      'signed out everywhere. This cannot be undone.',
          ),
          const SizedBox(height: 12),
          const Text(
            'If this is the only account, the Quark returns to setup and has '
            'to be set up again before anyone can use it.',
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('delete_account_files_warning'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kDeleteAccountFilesWarning,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Enter your password to confirm.'),
          const SizedBox(height: 8),
          ConfirmPasswordField(
            keyPrefix: 'delete_account',
            controller: _passwordController,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('delete_account_cancel'),
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('delete_account_submit'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _hasPassword ? _submit : null,
          child: const Text('Delete my account'),
        ),
      ],
    );
  }
}
