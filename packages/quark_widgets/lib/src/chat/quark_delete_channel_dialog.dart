import 'package:flutter/material.dart';

import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';

/// Asks before a chat channel is deleted, by having the channel's name typed
/// in: its history can't be recovered, so a tap alone is not enough.
///
/// The confirm button, drawn in the error color, stays off until the field
/// holds exactly [channelName]. It does not close itself: [onConfirm] and
/// [onCancel] fire, and the caller that pushed the dialog pops it once the
/// Quark has deleted the channel. While that request is out the caller passes
/// [isSubmitting], and a refusal comes back in as [error].
///
/// Key prefixes: `delete_channel_field`, `delete_channel_cancel`, and
/// `delete_channel_confirm`.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (ctx) => QuarkDeleteChannelDialog(
///     channelName: 'design',
///     isSubmitting: controller.isSaving,
///     error: deleteError,
///     onConfirm: delete,
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class QuarkDeleteChannelDialog extends StatefulWidget {
  /// Creates the confirmation for deleting [channelName].
  const QuarkDeleteChannelDialog({
    required this.channelName,
    required this.onConfirm,
    required this.onCancel,
    this.isSubmitting = false,
    this.error,
    super.key,
  });

  /// The channel's name, without a `#`: what must be typed to confirm.
  final String channelName;

  /// Called when the confirm button is tapped with the name typed.
  final VoidCallback onConfirm;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  /// Whether the channel is being deleted. Disables both buttons.
  final bool isSubmitting;

  /// A sentence saying why the delete was refused, composed by the caller.
  final String? error;

  @override
  State<QuarkDeleteChannelDialog> createState() =>
      _QuarkDeleteChannelDialogState();
}

class _QuarkDeleteChannelDialogState extends State<QuarkDeleteChannelDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      !widget.isSubmitting && _typed.text.trim() == widget.channelName;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = widget.error;

    return AlertDialog(
      scrollable: true,
      title: Text('Delete #${widget.channelName}?'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Every message in it, its keys, and who can see it are deleted '
              "for everyone. This can't be undone.",
            ),
            SizedBox(height: tokens.spacingMd),
            TextField(
              key: const ValueKey('delete_channel_field'),
              controller: _typed,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Type ${widget.channelName} to confirm',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_canConfirm) widget.onConfirm();
              },
            ),
            if (error != null) ...[
              SizedBox(height: tokens.spacingSm),
              Text(error, style: TextStyle(color: tokens.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('delete_channel_cancel'),
          onPressed: widget.isSubmitting ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('delete_channel_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: tokens.error,
            foregroundColor: tokens.errorForeground,
          ),
          onPressed: _canConfirm ? widget.onConfirm : null,
          child: widget.isSubmitting
              ? const QuarkLoader(size: 20)
              : const Text('Delete'),
        ),
      ],
    );
  }
}
