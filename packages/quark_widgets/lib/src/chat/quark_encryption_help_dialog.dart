import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// Explains chat encryption in household words: what a channel key is, how
/// members get it, and what "verified" and "unverified" mean. Shown from an
/// encryption line's "(?)" in `QuarkMessageList` and from
/// `QuarkEncryptionNotice`'s "What does this mean?".
///
/// It does not close itself: [onClose] fires and the caller that pushed it
/// pops it.
///
/// Key prefixes: `encryption_help_close` on the close button.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (ctx) =>
///       QuarkEncryptionHelpDialog(onClose: () => Navigator.of(ctx).pop()),
/// );
/// ```
class QuarkEncryptionHelpDialog extends StatelessWidget {
  /// Creates the explainer.
  const QuarkEncryptionHelpDialog({required this.onClose, super.key});

  /// Called when the close button is tapped.
  final VoidCallback onClose;

  /// What the dialog says, as (heading, paragraph) pairs, in order.
  static const List<(String, String)> paragraphs = [
    (
      'Encryption',
      'Messages are scrambled on your device before they leave it, and only '
          'members of the channel can unscramble them. Not even the Quark '
          'itself can read them.',
    ),
    (
      'Keys',
      'Each channel has a key, a secret that unscrambles its messages. A '
          'member who has it shares it with new members automatically. A new '
          'key is made when someone leaves, so they can\'t read what comes '
          'after.',
    ),
    (
      'Verified and unverified',
      'A change is verified when Quark can confirm, by a digital signature, '
          'which member made it. Unverified means it had no signature, or one '
          'that didn\'t check out, so Quark can\'t vouch for who made it. '
          'Messages keep working. If no one in the channel expected the '
          'change, tell an admin.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return AlertDialog(
      scrollable: true,
      icon: Icon(QuarkIcons.lock_outline, color: tokens.primary),
      title: const Text('How chat encryption works'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (heading, paragraph) in paragraphs) ...[
              Text(
                heading,
                style: TextStyle(
                  color: tokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: tokens.spacingXs),
              Text(paragraph, style: TextStyle(color: tokens.mutedForeground)),
              SizedBox(height: tokens.spacingMd),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('encryption_help_close'),
          onPressed: onClose,
          child: const Text('Got it'),
        ),
      ],
    );
  }
}
