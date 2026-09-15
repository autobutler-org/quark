import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// Asks before something is deleted: a title, a sentence on what happens,
/// and a confirm button drawn in the error color.
///
/// Generic on purpose. The caller writes the copy for what is being deleted,
/// and names the keys with [keyPrefix], so the same dialog confirms deleting
/// an account, a group, or anything else.
///
/// It does not close itself: [onConfirm] and [onCancel] fire, and the caller
/// that pushed the dialog pops it.
///
/// Key prefixes: `<keyPrefix>_confirm` and `<keyPrefix>_cancel`, for example
/// `delete_user_confirm`.
///
/// ```dart
/// showDialog<bool>(
///   context: context,
///   builder: (ctx) => ConfirmDeleteDialog(
///     title: 'Delete bob?',
///     body: 'Their files stay on this Quark and become yours.',
///     keyPrefix: 'delete_user',
///     onConfirm: () => Navigator.of(ctx).pop(true),
///     onCancel: () => Navigator.of(ctx).pop(false),
///   ),
/// );
/// ```
class ConfirmDeleteDialog extends StatelessWidget {
  /// Creates the confirmation titled [title].
  const ConfirmDeleteDialog({
    required this.title,
    required this.body,
    required this.keyPrefix,
    required this.onConfirm,
    required this.onCancel,
    this.confirmLabel = 'Delete',
    super.key,
  });

  /// The question, naming what is about to be deleted.
  final String title;

  /// What deleting it does, and what it leaves behind.
  final String body;

  /// The start of both button keys: `<keyPrefix>_confirm` and
  /// `<keyPrefix>_cancel`.
  final String keyPrefix;

  /// The confirm button's label.
  final String confirmLabel;

  /// Called when the confirm button is tapped.
  final VoidCallback onConfirm;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          key: ValueKey('${keyPrefix}_cancel'),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey('${keyPrefix}_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: tokens.error,
            foregroundColor: tokens.errorForeground,
          ),
          onPressed: onConfirm,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
