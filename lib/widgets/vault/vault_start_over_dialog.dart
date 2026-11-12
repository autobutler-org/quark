import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/confirm_password_field.dart';

/// The confirmation for starting the vault over: deleting every saved login
/// and the vault key, on every device (#3615).
///
/// Data in, callbacks out: it neither deletes anything nor closes itself.
/// [onConfirm] fires with the typed password, and the caller that pushed the
/// dialog is the one that pops it.
///
/// The confirmation is the login password, not a tap: anyone holding a
/// signed-in device could tap, and the wipe cannot be undone. It is the
/// password the user signs in with, which they know even when it no longer
/// opens the vault, since after a recovery it is the new one. The Quark checks
/// it; this dialog only refuses to send an empty one.
///
/// Key prefixes: `vault_start_over_password_field`,
/// `vault_start_over_password_visibility`, `vault_start_over_cancel`, and
/// `vault_start_over_confirm`.
///
/// ```dart
/// QuarkWidget.showDialog<String>(
///   context,
///   builder: (ctx) => VaultStartOverDialog(
///     onConfirm: (password) => Navigator.of(ctx).pop(password),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class VaultStartOverDialog extends StatefulWidget {
  /// Creates the start-over confirmation.
  const VaultStartOverDialog({
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  /// Called with the typed password, once one has been typed.
  final ValueChanged<String> onConfirm;

  /// Called when the user backs out through the cancel button.
  final VoidCallback onCancel;

  @override
  State<VaultStartOverDialog> createState() => _VaultStartOverDialogState();
}

class _VaultStartOverDialogState extends State<VaultStartOverDialog> {
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

    return QuarkWidget.alertDialog(
      title: const Text('Delete your vault?'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Every saved login is deleted, on every device, and nobody can '
            'get them back. Do this only if your password no longer opens '
            'the vault, then set up a new one.',
          ),
          const SizedBox(height: 16),
          const Text('Enter the password you sign in to Quark with.'),
          const SizedBox(height: 8),
          ConfirmPasswordField(
            keyPrefix: 'vault_start_over',
            controller: _passwordController,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('vault_start_over_cancel'),
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('vault_start_over_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _hasPassword ? _submit : null,
          child: const Text('Delete vault'),
        ),
      ],
    );
  }
}
