import 'package:flutter/painting.dart' show Color;

/// One color a formatting menu offers, with the name the menu shows for it.
class DataSheetSwatch {
  /// What the menu calls the color, for example "Green".
  final String name;

  /// The color itself.
  final Color color;

  /// A named color.
  const DataSheetSwatch(this.name, this.color);
}

/// The colors `DataSheetFormatBar` offers when the app passes none.
///
/// This package draws no theme of its own, so this is its one palette of
/// literal colors: mid-tone hues readable on both light and dark sheets, with
/// fills at a quarter opacity so the theme's text stays legible over them. An
/// app with design tokens should pass swatches derived from them instead, as
/// Quark does from `QuarkTokens`.
abstract final class DataSheetPalette {
  /// Text colors.
  static const List<DataSheetSwatch> text = [
    DataSheetSwatch('Gray', Color(0xFF64748B)),
    DataSheetSwatch('Red', Color(0xFFDC2626)),
    DataSheetSwatch('Amber', Color(0xFFD97706)),
    DataSheetSwatch('Green', Color(0xFF059669)),
    DataSheetSwatch('Blue', Color(0xFF0EA5E9)),
    DataSheetSwatch('Violet', Color(0xFF7C3AED)),
  ];

  /// Fill colors: [text]'s hues at a quarter opacity.
  static const List<DataSheetSwatch> fill = [
    DataSheetSwatch('Gray', Color(0x4064748B)),
    DataSheetSwatch('Red', Color(0x40DC2626)),
    DataSheetSwatch('Amber', Color(0x40D97706)),
    DataSheetSwatch('Green', Color(0x40059669)),
    DataSheetSwatch('Blue', Color(0x400EA5E9)),
    DataSheetSwatch('Violet', Color(0x407C3AED)),
  ];
}
