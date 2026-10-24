import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// Asks before something is deleted, or another step a person should
/// confirm: a title, a sentence on what happens (or richer [content]), and a
/// confirm button drawn in the error color unless [destructive] is false.
///
/// Generic on purpose. The caller writes the copy for what is about to
/// happen, and names the keys with [keyPrefix], so the same dialog confirms
/// deleting an account, moving duplicates to the trash, turning remote
/// access off, or restoring a file version.
///
/// The copy scrolls when the window is too short for it, so the buttons stay
/// reachable however long the copy or large the text (#2483).
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
    required this.keyPrefix,
    required this.onConfirm,
    required this.onCancel,
    this.body,
    this.content,
    this.confirmLabel = 'Delete',
    this.destructive = true,
    super.key,
  }) : assert(
         (body == null) != (content == null),
         'Pass exactly one of body and content.',
       );

  /// The question, naming what is about to be deleted.
  final String title;

  /// What deleting it does, and what it leaves behind. Pass this or
  /// [content].
  final String? body;

  /// The dialog's content when a sentence is not enough, such as a list of
  /// what goes. Pass this or [body].
  final Widget? content;

  /// Whether the confirm button wears the error color. False draws the
  /// plain filled button, for a step that loses nothing.
  final bool destructive;

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
      scrollable: true,
      title: Text(title),
      content: content ?? Text(body!),
      actions: [
        TextButton(
          key: ValueKey('${keyPrefix}_cancel'),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey('${keyPrefix}_confirm'),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: tokens.error,
                  foregroundColor: tokens.errorForeground,
                )
              : null,
          onPressed: onConfirm,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
