import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'quark_bar_icon_button.dart';

/// A labeled top bar action: a glyph and a word, in the same bordered, filled
/// shape as a [QuarkBarIconButton] and at the same height.
///
/// Create actions are chips rather than a bare `+`, because "Upload",
/// "New folder" and "New file" are three different things and a lone plus
/// cannot say which one it is (#2311). A chip is also the shape for a toggle
/// the user should be able to read the state of: [active] tints it with the
/// primary color.
///
/// A null [onPressed] renders it disabled.
///
/// On a phone — a viewport narrower than [compactBreakpoint] — a chip gives
/// its label up to its tooltip and renders as a [QuarkBarIconButton], so a bar
/// with a create action still fits in 360 pixels without dropping it. The
/// [active] tint does not survive that; a toggle whose state matters on a
/// phone belongs in a menu. [keepLabel] opts out, for the one chip whose word
/// is the point, such as the label on a collapsed menu.
///
/// Key prefixes: none of its own. Every bar action passes its own `key`.
///
/// ```dart
/// QuarkBarChip(
///   key: const ValueKey('docs_new'),
///   icon: QuarkIcons.add_rounded,
///   label: 'New document',
///   onPressed: createDocument,
/// );
/// ```
class QuarkBarChip extends StatelessWidget {
  /// Creates a chip reading [label] beside [icon].
  const QuarkBarChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.tooltip,
    this.keepLabel = false,
    super.key,
  });

  /// The viewport width below which a chip renders icon-only.
  static const double compactBreakpoint = 600;

  /// The glyph, from `QuarkIcons`.
  final IconData icon;

  /// The word on the chip.
  final String label;

  /// Runs the action. Null renders the chip disabled.
  final VoidCallback? onPressed;

  /// Whether the chip is a toggle that is currently on.
  final bool active;

  /// What the chip does, for a [label] that names a mode without explaining
  /// it (#2037). Null shows no tooltip: the label already says it.
  final String? tooltip;

  /// Whether the label stays on a phone. False drops it into the tooltip
  /// below [compactBreakpoint].
  final bool keepLabel;

  @override
  Widget build(BuildContext context) {
    if (!keepLabel && MediaQuery.sizeOf(context).width < compactBreakpoint) {
      return QuarkBarIconButton(
        icon: icon,
        tooltip: tooltip ?? label,
        onPressed: onPressed,
      );
    }
    final tokens = QuarkTokens.of(context);
    final foreground = active ? tokens.primary : tokens.secondaryForeground;
    final chip = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        iconColor: foreground,
        disabledForegroundColor: tokens.mutedForeground,
        disabledIconColor: tokens.mutedForeground,
        backgroundColor: active
            ? tokens.primary.withValues(alpha: 0.12)
            : tokens.input,
        disabledBackgroundColor: tokens.input,
        side: BorderSide(
          color: active ? tokens.primary.withValues(alpha: 0.3) : tokens.border,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
        ),
        iconSize: QuarkBarIconButton.glyphSize,
        textStyle: Theme.of(context).textTheme.labelLarge,
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingSm + tokens.spacingXs,
        ),
        minimumSize: const Size(0, QuarkBarIconButton.size),
        maximumSize: const Size(double.infinity, QuarkBarIconButton.size),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
    );
    final message = tooltip;
    return message == null ? chip : Tooltip(message: message, child: chip);
  }
}
