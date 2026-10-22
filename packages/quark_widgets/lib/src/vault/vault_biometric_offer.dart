import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// A card at the top of an open vault offering to open it with a face or
/// fingerprint next time, with a button that leads to the explanation and
/// one that puts the offer away.
///
/// It turns nothing on itself: [onEnable] should show what turning it on
/// means before anything is stored, and [onDismiss] hides the card for as
/// long as the caller decides.
///
/// Key prefixes: `vault_biometric_offer` on the card,
/// `vault_biometric_offer_enable` and `vault_biometric_offer_dismiss` on its
/// buttons.
///
/// ```dart
/// VaultBiometricOffer(
///   title: 'Unlock with Face ID?',
///   message: 'Open your vault on this device without typing your password.',
///   onEnable: showBiometricSettings,
///   onDismiss: biometric.dismissOffer,
/// );
/// ```
class VaultBiometricOffer extends StatelessWidget {
  /// Creates the offer.
  const VaultBiometricOffer({
    required this.title,
    required this.message,
    required this.onEnable,
    required this.onDismiss,
    this.enableLabel = 'Turn on',
    this.dismissLabel = 'Not now',
    super.key,
  });

  /// The question, naming the device's sensor.
  final String title;

  /// What it would save the user.
  final String message;

  /// Called when the enable button is tapped.
  final VoidCallback onEnable;

  /// Called when the dismiss button is tapped.
  final VoidCallback onDismiss;

  /// The enable button's label.
  final String enableLabel;

  /// The dismiss button's label.
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      key: const ValueKey('vault_biometric_offer'),
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
              Icon(QuarkIcons.fingerprint, size: 20, color: tokens.primary),
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
                          key: const ValueKey('vault_biometric_offer_dismiss'),
                          onPressed: onDismiss,
                          child: Text(dismissLabel),
                        ),
                        FilledButton(
                          key: const ValueKey('vault_biometric_offer_enable'),
                          onPressed: onEnable,
                          child: Text(enableLabel),
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
