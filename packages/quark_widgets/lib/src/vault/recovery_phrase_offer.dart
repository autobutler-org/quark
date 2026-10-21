import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// A card telling the user that a recovery would lose something, the vault
/// or their messages, until they add their recovery phrase to it, with a
/// button that leads to adding it and one that puts the card away.
///
/// It adds nothing itself: [onAdd] should ask for the phrase, and
/// [onDismiss] hides the card for as long as the caller decides.
///
/// Key prefixes: `recovery_phrase_offer` on the card,
/// `recovery_phrase_offer_add` and `recovery_phrase_offer_dismiss` on its
/// buttons.
///
/// ```dart
/// RecoveryPhraseOffer(
///   message: 'Add your recovery phrase so a recovery keeps your vault and '
///       'messages.',
///   onAdd: showAddRecoveryPhrase,
///   onDismiss: recoveryPhrase.dismiss,
/// );
/// ```
class RecoveryPhraseOffer extends StatelessWidget {
  /// Creates the offer.
  const RecoveryPhraseOffer({
    required this.message,
    required this.onAdd,
    required this.onDismiss,
    this.title = 'Add your recovery phrase',
    this.addLabel = 'Add phrase',
    this.dismissLabel = 'Not now',
    super.key,
  });

  /// The card's heading.
  final String title;

  /// What adding the phrase keeps, and what a recovery loses without it.
  final String message;

  /// Called when the add button is tapped.
  final VoidCallback onAdd;

  /// Called when the dismiss button is tapped.
  final VoidCallback onDismiss;

  /// The add button's label.
  final String addLabel;

  /// The dismiss button's label.
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      key: const ValueKey('recovery_phrase_offer'),
      padding: EdgeInsets.fromLTRB(
        tokens.spacingSm,
        tokens.spacingSm,
        tokens.spacingSm,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.card,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(QuarkIcons.key_rounded, size: 20, color: tokens.primary),
              SizedBox(width: tokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: tokens.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: tokens.spacingXs),
                    Text(
                      message,
                      style: TextStyle(color: tokens.mutedForeground),
                    ),
                    SizedBox(height: tokens.spacingSm),
                    Wrap(
                      spacing: tokens.spacingSm,
                      runSpacing: tokens.spacingXs,
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          key: const ValueKey('recovery_phrase_offer_dismiss'),
                          onPressed: onDismiss,
                          child: Text(dismissLabel),
                        ),
                        FilledButton(
                          key: const ValueKey('recovery_phrase_offer_add'),
                          onPressed: onAdd,
                          child: Text(addLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
