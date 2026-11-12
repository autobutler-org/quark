import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// How a [CopyButton] is drawn.
enum CopyButtonVariant {
  /// A bare [IconButton], for inline use in rows and toolbars.
  icon,

  /// An [OutlinedButton.icon] with a text label, for a standalone call to
  /// action.
  outlined,
}

/// A copy-to-clipboard button that leaves the clipboard itself to the caller.
///
/// The package has no platform channels, so [onCopy] does the writing and
/// whatever confirmation the app shows afterwards. Pass [unavailableReason]
/// when the clipboard cannot be used — an insecure web origin, say — and the
/// button renders disabled with that sentence as its tooltip.
///
/// Key prefixes: `copy_button` on the control itself.
///
/// ```dart
/// CopyButton(
///   text: token,
///   onCopy: (value) => clipboard.write(value),
///   unavailableReason: isClipboardAvailable ? null : 'Use HTTPS to enable',
/// );
/// ```
class CopyButton extends StatelessWidget {
  /// Creates a button that hands [text] to [onCopy] when pressed.
  const CopyButton({
    required this.text,
    required this.onCopy,
    this.icon = QuarkIcons.content_copy,
    this.iconSize = 16,
    this.label,
    this.unavailableReason,
    this.variant = CopyButtonVariant.icon,
    super.key,
  });

  /// The value handed to [onCopy]. Never rendered.
  final String text;

  /// Writes [text] wherever the app puts it, and confirms it however the app
  /// confirms things. Called only when the button is enabled.
  final Future<void> Function(String text) onCopy;

  /// The glyph on the button. Defaults to [QuarkIcons.content_copy].
  final IconData icon;

  /// The glyph size in logical pixels.
  final double iconSize;

  /// The label for [CopyButtonVariant.outlined]. Ignored by the icon variant,
  /// which falls back to a generic label when null.
  final String? label;

  /// Why copying is impossible right now, written by the app. Non-null
  /// disables the button and shows this as its tooltip.
  final String? unavailableReason;

  /// Whether to draw a bare icon or a labeled outlined button.
  final CopyButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final reason = unavailableReason;
    final available = reason == null;
    final tooltip = reason ?? 'Copy to clipboard';
    final onPressed = available ? () => onCopy(text) : null;

    switch (variant) {
      case CopyButtonVariant.icon:
        return IconButton(
          key: const ValueKey('copy_button'),
          icon: Icon(icon, size: iconSize),
          tooltip: tooltip,
          onPressed: onPressed,
        );
      case CopyButtonVariant.outlined:
        return Tooltip(
          message: available ? '' : tooltip,
          child: OutlinedButton.icon(
            key: const ValueKey('copy_button'),
            onPressed: onPressed,
            icon: Icon(icon, size: iconSize),
            label: Text(label ?? 'Copy to clipboard'),
          ),
        );
    }
  }
}
