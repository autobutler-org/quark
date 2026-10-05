import 'package:flutter/painting.dart' show Color;
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One color the slide editor's palettes offer, with the name a menu and a
/// screen reader use for it.
class SlideSwatch {
  /// A color called [name].
  const SlideSwatch(this.name, this.color);

  /// What the palette calls the color, such as "Green".
  final String name;

  /// The color as a slide stores it.
  final SlideColor color;
}

/// The ten theme color roles as swatches (#1163), each a
/// `SlideColor.theme` named for a person — "Text", "Background 2",
/// "Accent 1" — for the palettes to offer before any literal color.
List<SlideSwatch> themeSwatches() => [
  for (final role in ThemeColor.values)
    SlideSwatch(themeColorName(role), SlideColor.theme(role)),
];

/// What a palette calls the theme color [role]: "Background", "Text 2",
/// "Accent 3".
String themeColorName(ThemeColor role) {
  final words = role.name.replaceAllMapped(
    RegExp(r'(\d+)$'),
    (m) => ' ${m[1]}',
  );
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

/// The colors the slide editor's palettes offer: black and white, then the
/// colors of [tokens] in the order the sheets formatting toolbar lists them
/// (`sheetTextSwatches`), so a deck's colors match the rest of Quark.
///
/// A color repeated between tokens is listed once.
List<SlideSwatch> slideSwatches(QuarkTokens tokens) {
  final seen = <int>{};
  SlideSwatch of(String name, Color color) =>
      SlideSwatch(name, SlideColor(color.toARGB32()));
  return [
    for (final swatch in [
      const SlideSwatch('Black', SlideColor.black),
      const SlideSwatch('White', SlideColor.white),
      of('Gray', tokens.mutedForeground),
      of('Red', tokens.error),
      of('Amber', tokens.warning),
      of('Green', tokens.success),
      of('Blue', tokens.primary),
      for (final (i, color) in tokens.eventColors.indexed)
        of('Accent ${i + 1}', color),
    ])
      if (seen.add(swatch.color.argb)) swatch,
  ];
}
