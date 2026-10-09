import 'package:flutter/widgets.dart';
import 'package:quark_slides/quark_slides.dart';

/// One slide toolbar control as data: what it is called, its glyph, whether
/// it is on, and what it does. The wide rows and the phone menus draw the
/// same choices, so a control cannot be on one and missing from the other.
///
/// The `SlideToolbarActions` built from the editor's state hands these out.
class SlideToolbarChoice {
  /// A control keyed [key], reading [label].
  const SlideToolbarChoice({
    required this.key,
    required this.label,
    this.icon,
    this.selected,
    this.onSelected,
  });

  /// The control's `ValueKey`, in a row and in a menu alike.
  final String key;

  /// Its tooltip on a button and its text in a menu.
  final String label;

  /// Its glyph, from `QuarkIcons`; null in a menu of plain words.
  final IconData? icon;

  /// Whether it is on, for a toggle or one of a set; null for an action.
  final bool? selected;

  /// What choosing it does; null while it does not apply.
  final VoidCallback? onSelected;
}

/// A color control as data: the slide toolbar's text color, fill and
/// outline color.
class SlideColorChoice {
  /// A color control keyed [key], reading [label].
  const SlideColorChoice({
    required this.key,
    required this.label,
    required this.icon,
    required this.current,
    required this.noneLabel,
    this.theme,
    this.onChanged,
  });

  /// The control's `ValueKey`; its theme swatches are `<key>_theme_<role>`,
  /// its other swatches `<key>_<index>`, its none option `<key>_none` and
  /// its hex field `<key>_hex`.
  final String key;

  /// Its tooltip, and its heading in a menu.
  final String label;

  /// Its glyph, from `QuarkIcons`.
  final IconData icon;

  /// The color the selection shares; null when it has none or they differ,
  /// which leaves no swatch marked.
  final SlideColor? current;

  /// What the none option is called: "No fill", "Default", "Theme".
  final String noneLabel;

  /// The presentation's theme, which its role swatches are drawn in; null
  /// for a deck with none, drawn in `SlideThemes.light`.
  final SlideTheme? theme;

  /// Sets the color, null for none; null while the control does not apply.
  final ValueChanged<SlideColor?>? onChanged;
}
