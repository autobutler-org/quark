import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// A short card in an open vault about filling passwords in other apps:
/// whether this app is the device's autofill service, and one button that
/// opens the system setting that chooses it.
///
/// It only reports: [onOpenSettings] fires and the caller opens the
/// setting, then passes the new [isOn] once the user comes back. The
/// caller writes every word, since what the system setting is called
/// differs by platform.
///
/// Key prefixes: `vault_autofill_setup` on the card and
/// `vault_autofill_setup_open` on its button.
///
/// ```dart
/// VaultAutofillSetup(
///   isOn: status == AutofillStatus.enabled,
///   title: 'Fill passwords in other apps',
///   message: 'Choose Quark as your autofill service.',
///   actionLabel: 'Turn on autofill',
///   onOpenSettings: AutofillSettings.openSettings,
/// );
/// ```
class VaultAutofillSetup extends StatelessWidget {
  /// Creates the card.
  const VaultAutofillSetup({
    required this.isOn,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onOpenSettings,
    super.key,
  });

  /// Whether this app is the device's autofill service. Shows a check in
  /// place of the key icon.
  final bool isOn;

  /// The card's heading.
  final String title;

  /// What autofill does, or that it is on, in a sentence.
  final String message;

  /// The button's label, which says what the system screen is for.
  final String actionLabel;

  /// Called when the button is tapped.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      key: const ValueKey('vault_autofill_setup'),
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
              Icon(
                isOn
                    ? QuarkIcons.check_circle_outline
                    : QuarkIcons.key_outlined,
                size: 20,
                color: tokens.primary,
              ),
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
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: isOn
                          ? TextButton(
                              key: const ValueKey('vault_autofill_setup_open'),
                              onPressed: onOpenSettings,
                              child: Text(actionLabel),
                            )
                          : FilledButton(
                              key: const ValueKey('vault_autofill_setup_open'),
                              onPressed: onOpenSettings,
                              child: Text(actionLabel),
                            ),
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
