import 'package:flutter/material.dart';
import 'package:quark/controllers/vault_restore_controller.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/vault/restore/vault_restore_device_picker.dart';
import 'package:quark/widgets/vault/restore/vault_restore_summary.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Restores the vault from a backup drive (#1665): pick the drive, enter the
/// backup's recovery password, read what was restored.
///
/// It closes itself when the vault turns out to have locked. The page reloads
/// the vault once it closes, whichever way it went.
///
/// Keys: `vault_restore_password`, `vault_restore_cancel`,
/// `vault_restore_submit`, `vault_restore_done`, and those of
/// [VaultRestoreDevicePicker] and [VaultRestoreSummary].
///
/// ```dart
/// await VaultRestoreDialog.show(context);
/// ```
class VaultRestoreDialog extends StatefulWidget {
  /// The controller to drive, for a test passing fakes. The dialog disposes
  /// it. Defaults to one talking to the Quark.
  final VaultRestoreController? controller;

  const VaultRestoreDialog({super.key, this.controller});

  /// Opens the dialog and completes when it closes.
  static Future<void> show(BuildContext context) =>
      QuarkWidget.showDialog<void>(
        context,
        builder: (_) => const VaultRestoreDialog(),
      );

  @override
  State<VaultRestoreDialog> createState() => _VaultRestoreDialogState();
}

class _VaultRestoreDialogState extends State<VaultRestoreDialog> {
  late final VaultRestoreController _controller =
      widget.controller ?? VaultRestoreController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final restored = await _controller.restore(_password.text);
    if (!mounted) return;
    if (restored) _password.clear();
    if (_controller.vaultLocked) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _password]),
      builder: (context, _) {
        final result = _controller.result;
        final error = _controller.error;
        final canSubmit =
            _controller.selectedSerial != null &&
            _password.text.isNotEmpty &&
            !_controller.isRestoring;
        return QuarkWidget.alertDialog(
          title: const Text('Restore from backup drive'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: result != null
                ? VaultRestoreSummary(result: result)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pick the drive that holds your vault backup, then '
                        'enter the recovery password you chose when you '
                        'backed up. Entries already in your vault are left '
                        'unchanged.',
                      ),
                      const SizedBox(height: 16),
                      VaultRestoreDevicePicker(
                        devices: _controller.devices,
                        selectedSerial: _controller.selectedSerial,
                        isLoading: _controller.isLoading,
                        error: _controller.loadError,
                        onSelect: _controller.selectDevice,
                        onRetry: _controller.load,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('vault_restore_password'),
                        controller: _password,
                        obscureText: true,
                        enabled: !_controller.isRestoring,
                        decoration: const InputDecoration(
                          labelText: 'Recovery password',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) {
                          if (canSubmit) _submit();
                        },
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          actions: result != null
              ? [
                  TextButton(
                    key: const ValueKey('vault_restore_done'),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ]
              : [
                  TextButton(
                    key: const ValueKey('vault_restore_cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const ValueKey('vault_restore_submit'),
                    onPressed: canSubmit ? _submit : null,
                    child: _controller.isRestoring
                        ? const QuarkLoader(size: 20)
                        : const Text('Restore'),
                  ),
                ],
        );
      },
    );
  }
}
