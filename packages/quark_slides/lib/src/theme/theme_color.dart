/// A color role in a `SlideTheme`'s palette, which a slide refers to with
/// `SlideColor.theme(ThemeColor.accent1)` instead of a literal value, so
/// that changing the theme recolors the deck.
///
/// The roles follow the slots slide formats share — PowerPoint's `lt1`,
/// `dk1`, `lt2`, `dk2` and six accents — so a deck maps onto them on
/// export. [fallback] is the role's color in `SlideThemes.light`, what a
/// role reads as where no theme is at hand.
///
/// In `.qslide` a role color is written `theme:<name>`, as in
/// `"fill": "theme:accent1"`; a name this version does not know reads as
/// [text].
enum ThemeColor {
  /// The slide background.
  background(0xFFFFFFFF),

  /// Text on [background].
  text(0xFF1C1B1F),

  /// A second background, for panels and bands.
  background2(0xFFF1F3F6),

  /// Secondary text: subtitles, captions.
  text2(0xFF4B5563),

  /// The first accent: new shapes are filled with it.
  accent1(0xFF3366FF),

  /// The second accent.
  accent2(0xFF00A3A3),

  /// The third accent.
  accent3(0xFFF59E0B),

  /// The fourth accent.
  accent4(0xFFE5484D),

  /// The fifth accent.
  accent5(0xFF8B5CF6),

  /// The sixth accent.
  accent6(0xFF22C55E);

  const ThemeColor(this.fallback);

  /// The role's color, `0xAARRGGBB`, in the light theme.
  final int fallback;
}
