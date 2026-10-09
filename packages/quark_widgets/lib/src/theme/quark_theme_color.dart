import 'package:flutter/material.dart';

import 'quark_contrast.dart';
import 'quark_tokens.dart';

/// A theme color: the one color a person or an admin picks, from which a
/// whole [QuarkTokens] set is derived for light mode and for dark mode.
///
/// [classic] is the look Quark ships, neutral surfaces with a blue accent, and
/// yields `QuarkTokens.light` and `QuarkTokens.dark` untouched. Every other
/// theme color, a preset or a custom one from [QuarkThemeColor.fromSeed],
/// keeps only the hue of its seed and derives the rest in [tokensFor]:
/// clearly colored chrome, faintly tinted content surfaces, text for each,
/// and the accent, which nobody picks. It is saved as its [storageValue] and
/// read back with [parse].
///
/// ```dart
/// final themeColor = QuarkThemeColor.parse(settings.themeColor);
/// MaterialApp(
///   theme: QuarkTheme.light(themeColor: themeColor),
///   darkTheme: QuarkTheme.dark(themeColor: themeColor),
/// );
/// ```
@immutable
class QuarkThemeColor {
  const QuarkThemeColor._({
    required this.name,
    required this.label,
    required this.seed,
  });

  /// A custom theme color derived from [seed], which can be any color at all.
  ///
  /// Only the seed's hue is kept, and how colorful it is up to a point: a
  /// weakly saturated seed yields a proportionally grayer theme, one with no
  /// hue yields a gray one, and a vivid one is held to a calm strength. Its
  /// lightness and its alpha are ignored.
  QuarkThemeColor.fromSeed(Color seed)
    : this._(
        name: null,
        label: 'Custom',
        seed: Color(seed.toARGB32() | 0xFF000000),
      );

  /// The preset's stored name, such as `blue`. Null for a custom color.
  ///
  /// It has to match the shape the backend accepts:
  /// `^[a-z][a-z0-9-]{0,31}$`.
  final String? name;

  /// The name shown to a person: the preset's, or `Custom`.
  final String label;

  /// The color the theme is derived from. Null for [classic], which is not
  /// derived.
  final Color? seed;

  /// Whether this came from [QuarkThemeColor.fromSeed] rather than [presets].
  bool get isCustom => name == null;

  /// What to save: the preset's [name], or `#rrggbb` in lowercase for a
  /// custom [seed]. [parse] reads it back.
  String get storageValue {
    final name = this.name;
    if (name != null) return name;
    final rgb = seed!.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  /// The full token set this theme color yields for [brightness].
  ///
  /// [classic] returns the shipped set. Anything else is derived from the
  /// seed's hue, role by role, in HSL: each role starts from a saturation
  /// and lightness of its own and has its lightness moved only as far as it
  /// takes to reach the contrast that role needs against the surfaces it is
  /// drawn on. `docs/architecture/styling.md` has the table. Status colors,
  /// event colors, radii and spacing are the shipped ones.
  QuarkTokens tokensFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final seed = this.seed;
    if (seed == null) return dark ? QuarkTokens.dark : QuarkTokens.light;

    final hsl = HSLColor.fromColor(seed);
    final hue = hsl.hue;
    // How colorful: fading to gray for a weak seed, and never past
    // [_maxStrength].
    final k = (hsl.saturation / 0.5).clamp(0.0, _maxStrength);
    HSLColor at(double saturation, double lightness) =>
        HSLColor.fromAHSL(1, hue, saturation * k, lightness);
    // Text and accents move away from the surfaces: darker in light mode,
    // lighter in dark mode.
    final away = dark ? 1.0 : 0.0;

    // Tinted content. In light mode none of it goes darker than the classic
    // sidebar, so a status color scores no worse on it than it does there.
    Color surface(HSLColor start) => dark
        ? _paint(start)
        : _moveLightness(
            start,
            toward: 1,
            until: (color) =>
                color.computeLuminance() >= _lightSurfaceLuminance,
          );
    final background = surface(dark ? at(0.50, 0.063) : at(0.45, 0.968));
    final card = surface(dark ? at(0.45, 0.112) : at(0.60, 0.990));
    final input = surface(dark ? at(0.42, 0.127) : at(0.60, 0.990));
    final sidebar = surface(dark ? at(0.45, 0.086) : at(0.40, 0.950));
    final content = [background, card, input, sidebar];
    bool onContent(Color color, double ratio) =>
        content.every((surface) => contrastRatio(color, surface) >= ratio);

    // Colored chrome, lightened to a luminance its text and the accent can
    // both stand on: a mid tone in light mode, a deep one in dark. A
    // hue that is already lighter than that in light mode, a yellow, stays.
    final chrome = _moveLightness(
      dark ? at(0.70, 0.10) : at(0.80, 0.62),
      toward: 1,
      until: (color) =>
          color.computeLuminance() >=
          (dark ? _darkChromeLuminance : _lightChromeLuminance),
    );
    // A bar button on the chrome is filled with [input].
    bool onChrome(Color color, double ratio) =>
        contrastRatio(color, chrome) >= ratio &&
        contrastRatio(color, input) >= ratio;

    // The accent is drawn as text too, also on the tint of itself that marks
    // a selected chip, so it has to clear the text ratio there as well.
    bool accentOn(Color color, List<Color> surfaces) {
      final tint = color.withValues(alpha: _selectionTint);
      return surfaces.every(
        (surface) =>
            contrastRatio(color, surface) >= _text &&
            contrastRatio(color, Color.alphaBlend(tint, surface)) >= _text,
      );
    }

    final primaryStart = dark ? at(0.85, 0.60) : at(0.85, 0.45);
    final primary = _moveLightness(
      primaryStart,
      toward: away,
      until: (color) =>
          accentOn(color, content) && contrastRatio(color, chrome) >= _boundary,
    );
    // On chrome of its own hue the accent has further to go.
    final chromePrimary = _moveLightness(
      primaryStart,
      toward: away,
      until: (color) => accentOn(color, [...content, chrome]),
    );
    final foreground = _paint(dark ? at(0.30, 0.91) : at(0.45, 0.11));
    // A derived theme draws its hairlines at the boundary ratio too, so
    // dividers and control outlines are one color.
    final outline = _moveLightness(
      dark ? at(0.25, 0.40) : at(0.25, 0.62),
      toward: away,
      until: (color) => onContent(color, _boundary),
    );

    return (dark ? QuarkTokens.dark : QuarkTokens.light).copyWith(
      background: background,
      card: card,
      input: input,
      sidebar: sidebar,
      border: outline,
      outline: outline,
      foreground: foreground,
      cardForeground: foreground,
      secondaryForeground: _moveLightness(
        dark ? at(0.20, 0.65) : at(0.22, 0.34),
        toward: away,
        until: (color) => onContent(color, _secondaryText),
      ),
      mutedForeground: _moveLightness(
        dark ? at(0.16, 0.47) : at(0.18, 0.46),
        toward: away,
        until: (color) => onContent(color, _text),
      ),
      primary: primary,
      primaryForeground: moreLegibleOn(primary, _onDark, _onLight),
      chromePrimary: chromePrimary,
      chrome: chrome,
      chromeBorder: _moveLightness(
        dark ? at(0.40, 0.50) : at(0.50, 0.40),
        toward: away,
        until: (color) => contrastRatio(color, chrome) >= _boundary,
      ),
      chromeForeground: _paint(dark ? at(0.30, 0.94) : at(0.50, 0.09)),
      chromeSecondaryForeground: _moveLightness(
        dark ? at(0.30, 0.80) : at(0.45, 0.20),
        toward: away,
        until: (color) => onChrome(color, _secondaryText),
      ),
      chromeMutedForeground: _moveLightness(
        dark ? at(0.25, 0.70) : at(0.40, 0.30),
        toward: away,
        until: (color) => onChrome(color, _text),
      ),
    );
  }

  /// Quark as it ships: neutral surfaces and the blue accent. What an install
  /// nobody has themed looks like, and what [parse] falls back to.
  static const QuarkThemeColor classic = QuarkThemeColor._(
    name: 'classic',
    label: 'Classic',
    seed: null,
  );

  /// The blue preset.
  static const QuarkThemeColor blue = QuarkThemeColor._(
    name: 'blue',
    label: 'Blue',
    seed: Color(0xFF0EA5E9),
  );

  /// The indigo preset.
  static const QuarkThemeColor indigo = QuarkThemeColor._(
    name: 'indigo',
    label: 'Indigo',
    seed: Color(0xFF4F63E6),
  );

  /// The violet preset.
  static const QuarkThemeColor violet = QuarkThemeColor._(
    name: 'violet',
    label: 'Violet',
    seed: Color(0xFF8B5CF6),
  );

  /// The magenta preset.
  static const QuarkThemeColor magenta = QuarkThemeColor._(
    name: 'magenta',
    label: 'Magenta',
    seed: Color(0xFFD946EF),
  );

  /// The pink preset.
  static const QuarkThemeColor pink = QuarkThemeColor._(
    name: 'pink',
    label: 'Pink',
    seed: Color(0xFFEC4899),
  );

  /// The lime preset.
  static const QuarkThemeColor lime = QuarkThemeColor._(
    name: 'lime',
    label: 'Lime',
    seed: Color(0xFF84CC16),
  );

  /// The near-neutral preset: slate chrome and a slate accent, for a Quark
  /// that wants to be told apart without much color.
  static const QuarkThemeColor graphite = QuarkThemeColor._(
    name: 'graphite',
    label: 'Graphite',
    seed: Color(0xFF64748B),
  );

  /// Every preset, in the order a picker offers them: [classic] first.
  ///
  /// The hues keep at least 25 degrees from `error`, `warning` and `success`
  /// and from each other, so a theme is never mistaken for a status.
  static const List<QuarkThemeColor> presets = [
    classic,
    blue,
    indigo,
    violet,
    magenta,
    pink,
    lime,
    graphite,
  ];

  /// Reads a [storageValue] back: a preset's name, or `#rrggbb` for a custom
  /// seed.
  ///
  /// Null, empty, malformed, and a name this build has no preset for all
  /// return [classic]. The backend checks the shape only and keeps no list
  /// of presets, so a name saved by a newer client can reach an older one.
  static QuarkThemeColor parse(String? stored) {
    if (stored == null) return classic;
    for (final preset in presets) {
      if (preset.name == stored) return preset;
    }
    final hex = _hexSeed.firstMatch(stored)?.group(1);
    if (hex == null) return classic;
    return QuarkThemeColor.fromSeed(
      Color(0xFF000000 | int.parse(hex, radix: 16)),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuarkThemeColor &&
          other.name == name &&
          other.label == label &&
          other.seed == seed;

  @override
  int get hashCode => Object.hash(name, label, seed);

  @override
  String toString() => 'QuarkThemeColor($storageValue)';
}

/// How colorful a theme gets, as a share of the saturations [tokensFor]
/// starts each role from. At 1 the chrome and the accent are vivid enough to
/// tire the eye (#2777); `graphite` sits near a third and is left alone by
/// anything above that. The classic accent in `QuarkTokens` is written out
/// to match this value and does not follow a change to it.
const double _maxStrength = 0.45;

/// How far above a WCAG ratio a derived color is moved. Bisection stops the
/// moment a ratio holds, so without it pairs land exactly on 4.5 or 3.0,
/// where nothing is left for a rendering difference to take (#2785).
const double _margin = 0.1;

/// WCAG AA for text, plus [_margin]. Muted text, and the accent, which text
/// buttons, links and icons are drawn in, are held to it on every surface
/// they sit on.
const double _text = 4.5 + _margin;

/// What secondary text is held to, so it stays a step above muted text.
const double _secondaryText = 6;

/// How strongly the accent tints the fill behind a selected chip, segment or
/// badge, which the accent is then drawn on as text.
const double _selectionTint = 0.12;

/// WCAG's ratio for a boundary that identifies a control, an outline, plus
/// [_margin].
const double _boundary = 3 + _margin;

/// The darkest the chrome gets in light mode. At this luminance dark text
/// clears it, and so does an accent dark enough to be text on the content.
const double _lightChromeLuminance = 0.45;

/// The darkest a tinted content surface gets in light mode: just above the
/// luminance of the classic sidebar, `#F1F5F9`, which is 0.908.
const double _lightSurfaceLuminance = 0.91;

/// The luminance of the chrome in dark mode: deep enough for light text and
/// a bright accent, and far enough off the page to read as a color.
const double _darkChromeLuminance = 0.03;

/// Text on a dark fill.
const Color _onDark = Color(0xFFFFFFFF);

/// Text on a light fill: the dark card color.
const Color _onLight = Color(0xFF0F172A);

final RegExp _hexSeed = RegExp(r'^#([0-9a-f]{6})$', caseSensitive: false);

/// [color] as the 8-bit color that gets painted, which is what contrast has
/// to be measured on.
Color _paint(HSLColor color) => Color(color.toColor().toARGB32());

/// [start] with its lightness moved toward [toward] (0 or 1) only as far as
/// it takes for [until] to hold. A start that already holds is kept.
Color _moveLightness(
  HSLColor start, {
  required double toward,
  required bool Function(Color color) until,
}) {
  Color at(double lightness) => _paint(start.withLightness(lightness));

  if (until(_paint(start))) return _paint(start);
  // Luminance only rises with HSL lightness at a fixed hue and saturation,
  // so the nearest lightness that holds can be found by bisection.
  var failing = start.lightness;
  var holding = toward;
  for (var i = 0; i < 16; i++) {
    final mid = (failing + holding) / 2;
    if (until(at(mid))) {
      holding = mid;
    } else {
      failing = mid;
    }
  }
  return at(holding);
}
