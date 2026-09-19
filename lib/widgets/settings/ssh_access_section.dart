import 'package:flutter/material.dart';
import 'package:quark/controllers/ssh_access_controller.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/ssh_key_dialog.dart';
import 'package:quark/widgets/settings/ssh_password_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The admin's SSH access card on the settings page (#2131).
///
/// Owns an [SshAccessController] and maps it into the package
/// [SshAccessPanel]. The dialogs and snack bars are the app's part: a
/// confirmation before SSH is turned on, and prompts for keys and passwords.
class SshAccessSection extends StatefulWidget {
  /// Creates the section, with the real service unless [controller] is given.
  const SshAccessSection({this.controller, super.key});

  /// Injected for tests. Created and disposed here when null.
  final SshAccessController? controller;

  @override
  State<SshAccessSection> createState() => _SshAccessSectionState();
}

class _SshAccessSectionState extends State<SshAccessSection> {
  late final SshAccessController _controller =
      widget.controller ?? SshAccessController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _setEnabled(bool enabled) async {
    if (enabled) {
      final confirmed = await confirmAction(
        context,
        title: 'Turn on SSH access?',
        message:
            'Anyone on your network with an allowed key, or the password if '
            'you set one, can sign in to this Quark as quark and run commands '
            'on it. Port 22 opens in the firewall. Turn it off when you are '
            'done.',
        confirmLabel: 'Turn on',
      );
      if (confirmed != true) return;
    }
    await _controller.setEnabled(enabled);
  }

  Future<void> _addKey() async {
    final key = await QuarkWidget.showDialog<String>(
      context,
      builder: (ctx) => SshKeyDialog(
        onSubmit: (key) => Navigator.of(ctx).pop(key),
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
    if (key == null) return;
    await _controller.addKey(key);
  }

  Future<void> _removeKey(String fingerprint) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove key?',
      message: 'The key $fingerprint will no longer be able to sign in.',
      confirmLabel: 'Remove',
    );
    if (confirmed != true) return;
    await _controller.removeKey(fingerprint);
  }

  Future<void> _setPassword() async {
    final password = await QuarkWidget.showDialog<String>(
      context,
      builder: (ctx) => SshPasswordDialog(
        onSubmit: (password) => Navigator.of(ctx).pop(password),
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
    if (password == null) return;
    if (await _controller.setPassword(password)) _announce('SSH password set');
  }

  Future<void> _clearPassword() async {
    final confirmed = await confirmAction(
      context,
      title: 'Clear SSH password?',
      message: 'Only allowed keys will be able to sign in.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    if (await _controller.clearPassword()) _announce('SSH password cleared');
  }

  void _announce(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final status = _controller.status;
        return Card(
          child: SshAccessPanel(
            isLoading: _controller.isLoading && status == null,
            isWorking: _controller.isWorking,
            error: _controller.error,
            unavailableReason: _controller.unavailableReason,
            enabled: status?.enabled ?? false,
            keys: [
              for (final key in status?.keys ?? const [])
                SshKeyItem(
                  fingerprint: key.fingerprint,
                  type: key.type,
                  comment: key.comment,
                ),
            ],
            onEnabledChanged: _setEnabled,
            onAddKey: _addKey,
            onRemoveKey: _removeKey,
            onSetPassword: _setPassword,
            onClearPassword: _clearPassword,
          ),
        );
      },
    );
  }
}
