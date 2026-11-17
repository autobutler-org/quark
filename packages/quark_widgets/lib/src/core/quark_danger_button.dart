import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// A full-width outlined button in the error color, for an action that
/// destroys something, set apart at the bottom of a list rather than one
/// small icon away from a harmless one. The caller confirms before acting;
/// the button only reports the tap.
///
/// Key prefixes: none of its own; the key the caller passes lands on the
/// button.
///
/// ```dart
/// QuarkDangerButton(
///   key: const ValueKey('trash_empty'),
///   label: 'Empty trash',
///   icon: QuarkIcons.delete_forever_outlined,
///   onPressed: confirmAndEmpty,
/// );
/// ```
class QuarkDangerButton extends StatelessWidget {
  /// Creates a button reading [label].
  const QuarkDangerButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  /// What the button does, as a short verb phrase: "Empty trash".
  final String label;

  /// A glyph before [label], or null for none.
  final IconData? icon;

  /// Called on a tap. Null disables the button.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final icon = this.icon;
    final enabled = onPressed != null;
    return Padding(
      padding: EdgeInsets.all(tokens.spacingMd),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: icon == null ? null : Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: tokens.error,
            side: BorderSide(
              color: enabled
                  ? tokens.error
                  : tokens.error.withValues(alpha: 0.38),
            ),
            padding: EdgeInsets.symmetric(vertical: tokens.spacingMd),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
            ),
          ),
        ),
      ),
    );
  }
}
