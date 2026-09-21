import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';

/// The body of the add-SSH-key dialog: one field for a public key line.
///
/// Data in, callbacks out: it neither adds the key nor closes itself.
/// [onSubmit] fires with the trimmed key, and the caller that pushed the
/// dialog is the one that pops it. The Quark validates the key.
///
/// Key prefixes: `ssh_key_field`, `ssh_key_cancel`, and `ssh_key_submit`.
///
/// ```dart
/// QuarkWidget.showDialog<String>(
///   context,
///   builder: (ctx) => SshKeyDialog(
///     onSubmit: (key) => Navigator.of(ctx).pop(key),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class SshKeyDialog extends StatefulWidget {
  /// Creates the dialog body.
  const SshKeyDialog({
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  /// Called with the pasted key, trimmed and not empty.
  final ValueChanged<String> onSubmit;

  /// Called when the user backs out through the cancel button.
  final VoidCallback onCancel;

  @override
  State<SshKeyDialog> createState() => _SshKeyDialogState();
}

class _SshKeyDialogState extends State<SshKeyDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _key => _controller.text.trim();

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: const Text('Add SSH key'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste a public key, such as the contents of ~/.ssh/id_ed25519.pub. '
            'Never paste a private key.',
          ),
          const SizedBox(height: 12),
          QuarkWidget.textField(
            key: const ValueKey('ssh_key_field'),
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 3,
            maxLines: 6,
            hintText: 'ssh-ed25519 AAAA... you@laptop',
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('ssh_key_cancel'),
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('ssh_key_submit'),
          onPressed: _key.isEmpty ? null : () => widget.onSubmit(_key),
          child: const Text('Add key'),
        ),
      ],
    );
  }
}
