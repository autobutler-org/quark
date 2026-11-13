import 'package:material_ui/material_ui.dart';

/// The glyph a menu row draws, the same size as a bar chip's.
const double quarkMenuIconSize = 18;

/// The space between a menu row's glyph and its label.
///
/// This is the gap [OutlinedButton.icon] uses at the default text size, which
/// is what a bar chip is. Flutter's own menu row leaves 12.
const double quarkMenuIconGap = 8;

/// Lays out [label] beside [leading] and [trailing] the way a bar chip lays
/// out its glyph and word.
///
/// [MenuItemButton.leadingIcon] leaves a wider gap than that chip, and a
/// narrower glyph then sits apart from the word. Every icon is the same box,
/// so the labels share one left edge. A trailing check follows the label by
/// that same gap.
///
/// The row stays as wide as its contents. A flexible gap would grow to the
/// widest constraint the menu offers, which on a phone is wider than the
/// screen, and the row's center would sit past the edge where a tap cannot
/// land.
///
/// The row is the [MenuItemButton.child] or the [PopupMenuItem.child]. It is
/// not a [MenuItemButton] itself.
Widget quarkMenuLabel({
  Widget? leading,
  Widget? trailing,
  required Widget label,
}) {
  Widget slot(Widget icon) {
    return SizedBox(
      width: quarkMenuIconSize,
      height: quarkMenuIconSize,
      child: IconTheme.merge(
        data: const IconThemeData(size: quarkMenuIconSize),
        child: Center(child: icon),
      ),
    );
  }

  // Packed from the start, and no wider than its contents. A flexible gap
  // grows to the menu's maximum constraint, which is the overlay, so a
  // checked row on a phone ends past the screen.
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (leading != null) ...[
        slot(leading),
        const SizedBox(width: quarkMenuIconGap),
      ],
      label,
      if (trailing != null) ...[
        const SizedBox(width: quarkMenuIconGap),
        slot(trailing),
      ],
    ],
  );
}
