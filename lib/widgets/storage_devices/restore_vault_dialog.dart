import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';

/// Asks an admin to restore every vault from this snapshot-backup drive, and
/// to enter their own login password again.
///
/// Pops with that password, or with nothing on Cancel. An empty password does
/// not confirm. The dialog owns its text controller, so it lives until the
/// route has finished animating out (#3102).
class RestoreVaultDialog extends StatefulWidget {
  /// Creates the dialog.
  const RestoreVaultDialog({super.key});

  @override
  State<RestoreVaultDialog> createState() => _RestoreVaultDialogState();
}

class _RestoreVaultDialogState extends State<RestoreVaultDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _confirm() {
    final password = _password.text;
    if (password.isEmpty) return;
    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: const Text('Restore vaults from this drive'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Each vault goes to the account with exactly the same username. '
            'Carol is not carol.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Every vault in the backup must have its account here first, or '
            'nothing is restored.',
          ),
          const SizedBox(height: 12),
          const Text(
            'After a move to new hardware, each person unlocks their vault '
            'with the password they had when the backup was taken.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('restore_vault_password'),
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Your login password',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('restore_vault_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('restore_vault_confirm'),
          onPressed: _password.text.isEmpty ? null : _confirm,
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
