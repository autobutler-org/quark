import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';

/// The shortest SSH login password the Quark accepts. Mirrors
/// `sshutil.MinPasswordLength`; the Quark checks it again.
const int kSshMinPasswordLength = 12;

/// The body of the set-SSH-password dialog: the password, typed twice.
///
/// Data in, callbacks out: it neither sets the password nor closes itself.
/// [onSubmit] fires once both fields match and are long enough, and the
/// caller that pushed the dialog is the one that pops it.
///
/// Key prefixes: `ssh_password_field`, `ssh_password_confirm_field`,
/// `ssh_password_cancel`, and `ssh_password_submit`.
///
/// ```dart
/// QuarkWidget.showDialog<String>(
///   context,
///   builder: (ctx) => SshPasswordDialog(
///     onSubmit: (password) => Navigator.of(ctx).pop(password),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class SshPasswordDialog extends StatefulWidget {
  /// Creates the dialog body.
  const SshPasswordDialog({
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  /// Called with the new password.
  final ValueChanged<String> onSubmit;

  /// Called when the user backs out through the cancel button.
  final VoidCallback onCancel;

  @override
  State<SshPasswordDialog> createState() => _SshPasswordDialogState();
}

class _SshPasswordDialogState extends State<SshPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _password.text.length >= kSshMinPasswordLength &&
      _password.text == _confirm.text;

  void _submit() {
    if (_isValid) widget.onSubmit(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: const Text('Set SSH password'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This is the password for signing in as quark over SSH. '
            'At least $kSshMinPasswordLength characters. Quark does not '
            'store it, so keep it somewhere safe.',
          ),
          const SizedBox(height: 12),
          QuarkWidget.textField(
            key: const ValueKey('ssh_password_field'),
            controller: _password,
            autofocus: true,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            hintText: 'Password',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          QuarkWidget.textField(
            key: const ValueKey('ssh_password_confirm_field'),
            controller: _confirm,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            hintText: 'Type it again',
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('ssh_password_cancel'),
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('ssh_password_submit'),
          onPressed: _isValid ? _submit : null,
          child: const Text('Set password'),
        ),
      ],
    );
  }
}
