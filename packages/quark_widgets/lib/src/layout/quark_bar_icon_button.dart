import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// A square, bordered, filled icon button: the one shape a top bar action
/// takes, on every page.
///
/// Files used to draw its bar buttons this way while every other page used a
/// bare [IconButton], so the same action looked like a button on one page and
/// a loose glyph on the next (#2311). Every bar action — select, search,
/// refresh, the theme toggle, the jobs badge — is one of these now, at one
/// glyph size.
///
/// A null [onPressed] renders it disabled rather than hiding it, so a bar
/// keeps its shape as an action comes and goes. [isBusy] swaps the glyph for
/// a spinner and refuses taps, for an action that is already running.
///
/// Key prefixes: none of its own. Every bar action passes its own `key`, and
/// that is the one a test or a `.probe` script reaches for.
///
/// ```dart
/// QuarkBarIconButton(
///   key: const ValueKey('trash_select'),
///   icon: QuarkIcons.check_circle_outline,
///   tooltip: 'Select',
///   onPressed: controller.enterSelection,
/// );
/// ```
class QuarkBarIconButton extends StatelessWidget {
  /// Creates a bar button showing [icon], explained by [tooltip].
  const QuarkBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isBusy = false,
    this.destructive = false,
    super.key,
  });

  /// The glyph size every bar action shares.
  static const double glyphSize = 18;

  /// The button's outer edge: the glyph, its padding, and the border.
  static const double size = 36;

  /// The glyph, from `QuarkIcons`.
  final IconData icon;

  /// What the button does, shown on hover and read by screen readers. Every
  /// bar action has one; an unexplained glyph is how the vault's menu ended
  /// up anonymous.
  final String tooltip;

  /// Runs the action. Null renders the button disabled.
  final VoidCallback? onPressed;

  /// Whether the action is already running. True shows a spinner in place of
  /// [icon] and blocks further taps.
  final bool isBusy;

  /// Whether the action destroys something, which draws the glyph in the
  /// error color.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final color = destructive ? tokens.error : tokens.secondaryForeground;
    return IconButton(
      tooltip: tooltip,
      onPressed: isBusy ? null : onPressed,
      iconSize: glyphSize,
      style: IconButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: tokens.mutedForeground,
        backgroundColor: tokens.input,
        disabledBackgroundColor: tokens.input,
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(size),
        maximumSize: const Size.square(size),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
      icon: isBusy
          ? SizedBox.square(
              dimension: glyphSize,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon),
    );
  }
}
