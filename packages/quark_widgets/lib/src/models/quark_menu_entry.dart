import 'package:flutter/widgets.dart';

/// One row of an item's menu, as `showQuarkMenu` and `QuarkMenuButton` draw
/// it, or a divider between rows.
///
/// The row runs [onSelected] after the menu has closed, so a dialog or sheet
/// it opens lands over the page rather than over the menu. Leave
/// [onSelected] null to show the row disabled.
@immutable
class QuarkMenuEntry {
  /// Creates a row reading [label].
  const QuarkMenuEntry({
    required this.label,
    required this.onSelected,
    this.icon,
    this.key,
    this.destructive = false,
    this.busy = false,
  }) : isDivider = false;

  /// Creates a thin line between two groups of rows.
  const QuarkMenuEntry.divider()
    : label = '',
      onSelected = null,
      icon = null,
      key = null,
      destructive = false,
      busy = false,
      isDivider = true;

  /// The row's text.
  final String label;

  /// Runs once the menu has closed. Null disables the row.
  final VoidCallback? onSelected;

  /// A glyph before [label], or null for none.
  final IconData? icon;

  /// Set on the row, so a `.probe` script or a test can pick it.
  final Key? key;

  /// Draws the row in the error color, for an action that removes something.
  final bool destructive;

  /// Shows a small loader in place of [icon], for an action already running.
  final bool busy;

  /// Whether this is a divider rather than a row.
  final bool isDivider;
}
