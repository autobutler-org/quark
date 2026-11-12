import 'package:material_ui/material_ui.dart';

import '../core/quark_loader.dart';
import '../theme/quark_theme.dart';
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
/// The visual is a [size] square, but the button takes a [tapTargetSize]
/// square in layout and answers taps across all of it: the 48dp minimum
/// touch target (#2605). A bar lays its controls out with no gap of their
/// own, because that [tapTargetMargin] is the gap.
///
/// A null [onPressed] renders it disabled rather than hiding it, so a bar
/// keeps its shape as an action comes and goes. [isBusy] swaps the glyph for
/// a spinner and refuses taps, for an action that is already running.
///
/// [selected] makes it a toggle a user can read the state of — bold in a
/// formatting row, the active drawing tool — tinted with the primary color
/// as an active [QuarkBarChip] is, and announced as on or off to a screen
/// reader. Left null, it is a plain action.
///
/// [badge] hangs a count over the top end corner, inside the tap target, so it
/// grows toward the glyph rather than past the bar's edge or out of a
/// scrolling row's clip.
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
    this.onLongPress,
    this.isBusy = false,
    this.destructive = false,
    this.selected,
    this.badge,
    super.key,
  });

  /// The glyph size every bar action shares.
  static const double glyphSize = 18;

  /// The button's visible edge: the glyph, its padding, and the border.
  static const double size = 36;

  /// The square the button takes in layout and answers taps in: the 48dp
  /// minimum touch target, with the [size] visual centered in it.
  static const double tapTargetSize = kMinInteractiveDimension;

  /// The tappable margin on each side of the visual, which is also the space
  /// a bar leaves between two controls.
  static const double tapTargetMargin = (tapTargetSize - size) / 2;

  /// The glyph, from `QuarkIcons`.
  final IconData icon;

  /// What the button does, shown on hover and read by screen readers. Every
  /// bar action has one; an unexplained glyph is how the vault's menu ended
  /// up anonymous. Null only for a disabled button whose tooltip would name
  /// something that is not there, such as Files' back arrow at the top.
  final String? tooltip;

  /// Runs the action. Null renders the button disabled.
  final VoidCallback? onPressed;

  /// Runs a second action on a long press, such as a choice the plain tap
  /// skips. Null leaves a long press to the tooltip.
  final VoidCallback? onLongPress;

  /// Whether the action is already running. True shows a spinner in place of
  /// [icon] and blocks further taps.
  final bool isBusy;

  /// Whether the action destroys something, which draws the glyph in the
  /// error color.
  final bool destructive;

  /// Whether the button is a toggle that is on; null for a plain action.
  final bool? selected;

  /// A childless [Badge] drawn over the top end corner, or null for none.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final on = selected ?? false;
    final color = destructive
        ? tokens.error
        : on
        ? tokens.primary
        : tokens.secondaryForeground;
    final button = IconButton(
      tooltip: tooltip,
      isSelected: selected,
      onPressed: isBusy ? null : onPressed,
      onLongPress: isBusy ? null : onLongPress,
      iconSize: glyphSize,
      style:
          IconButton.styleFrom(
            foregroundColor: color,
            disabledForegroundColor: tokens.mutedForeground,
            backgroundColor: on
                ? tokens.primary.withValues(alpha: 0.12)
                : tokens.input,
            disabledBackgroundColor: tokens.input,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
            ),
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(size),
            maximumSize: const Size.square(size),
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            // Through the theme's focus outline: a side of its own would replace
            // it, and on the input fill a focused button looked like any other
            // (#2604).
          ).copyWith(
            side: QuarkTheme.focusRing(
              tokens,
              resting: on
                  ? tokens.primary.withValues(alpha: 0.3)
                  : tokens.border,
            ),
          ),
      icon: isBusy ? QuarkLoader(size: glyphSize) : Icon(icon),
    );
    final badge = this.badge;
    if (badge == null) return button;
    return Stack(
      children: [
        button,
        PositionedDirectional(top: tapTargetMargin / 2, end: 0, child: badge),
      ],
    );
  }
}
