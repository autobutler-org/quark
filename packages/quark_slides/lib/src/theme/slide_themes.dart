import '../model/slide_color.dart';
import '../model/stroke.dart';
import 'slide_theme.dart';
import 'theme_color.dart';
import 'theme_palette.dart';
import 'theme_shape_style.dart';
import 'theme_text_style.dart';

/// The themes the package ships: [light], [dark], [warm], [cool] and
/// [highContrast], in [all].
///
/// Each is plain values a host can restyle: copy one with
/// `SlideTheme.copyWith` and swap in its own tokens. Their palettes keep
/// [ThemeColor.text] and [ThemeColor.text2] at a contrast ratio of at least
/// 4.5:1 against [ThemeColor.background] (7:1 in [highContrast]).
///
/// ```dart
/// for (final theme in SlideThemes.all) ThemeCard(theme: theme);
/// SlideThemes.byId('dark'); // SlideThemes.dark
/// ```
abstract final class SlideThemes {
  /// Black text on white, with a blue first accent: [ThemeColor]'s
  /// fallbacks.
  static final light = SlideTheme(
    id: 'light',
    name: 'Light',
    colors: ThemePalette({
      for (final role in ThemeColor.values) role: role.fallback,
    }),
  );

  /// Light text on near-black, with brighter accents.
  static final dark = SlideTheme(
    id: 'dark',
    name: 'Dark',
    colors: ThemePalette({
      ThemeColor.background: 0xFF121318,
      ThemeColor.text: 0xFFF3F4F6,
      ThemeColor.background2: 0xFF1F2229,
      ThemeColor.text2: 0xFFA9B0BC,
      ThemeColor.accent1: 0xFF7AA2FF,
      ThemeColor.accent2: 0xFF4FD1C5,
      ThemeColor.accent3: 0xFFFBBF24,
      ThemeColor.accent4: 0xFFFF7A80,
      ThemeColor.accent5: 0xFFB69CFF,
      ThemeColor.accent6: 0xFF6EE7A0,
    }),
  );

  /// Brown text on cream, with earthy accents and serif titles.
  static final warm = SlideTheme(
    id: 'warm',
    name: 'Warm',
    headingFont: 'Georgia',
    colors: ThemePalette({
      ThemeColor.background: 0xFFFFF8F0,
      ThemeColor.text: 0xFF3B2A20,
      ThemeColor.background2: 0xFFF6E7D8,
      ThemeColor.text2: 0xFF7A5C48,
      ThemeColor.accent1: 0xFFC2410C,
      ThemeColor.accent2: 0xFFB45309,
      ThemeColor.accent3: 0xFFA16207,
      ThemeColor.accent4: 0xFFBE123C,
      ThemeColor.accent5: 0xFF9D174D,
      ThemeColor.accent6: 0xFF4D7C0F,
    }),
  );

  /// Navy text on a pale blue-gray, with blue and teal accents.
  static final cool = SlideTheme(
    id: 'cool',
    name: 'Cool',
    colors: ThemePalette({
      ThemeColor.background: 0xFFF4F8FB,
      ThemeColor.text: 0xFF0F2533,
      ThemeColor.background2: 0xFFE2ECF3,
      ThemeColor.text2: 0xFF44606F,
      ThemeColor.accent1: 0xFF0E7490,
      ThemeColor.accent2: 0xFF1D4ED8,
      ThemeColor.accent3: 0xFF0369A1,
      ThemeColor.accent4: 0xFF4338CA,
      ThemeColor.accent5: 0xFF0F766E,
      ThemeColor.accent6: 0xFF64748B,
    }),
  );

  /// White and yellow on black, with larger text and outlined
  /// shapes, for low vision and bright rooms.
  static final highContrast = SlideTheme(
    id: 'highContrast',
    name: 'High contrast',
    colors: ThemePalette({
      ThemeColor.background: 0xFF000000,
      ThemeColor.text: 0xFFFFFFFF,
      ThemeColor.background2: 0xFF1A1A1A,
      ThemeColor.text2: 0xFFFFFF00,
      ThemeColor.accent1: 0xFFFFD400,
      ThemeColor.accent2: 0xFF00E5FF,
      ThemeColor.accent3: 0xFFFF6EC7,
      ThemeColor.accent4: 0xFF7CFF4F,
      ThemeColor.accent5: 0xFFFFFFFF,
      ThemeColor.accent6: 0xFFFF9F1C,
    }),
    title: const ThemeTextStyle(fontSize: 64, heading: true),
    subtitle: const ThemeTextStyle(
      fontSize: 44,
      color: SlideColor.theme(ThemeColor.text2),
    ),
    body: const ThemeTextStyle(fontSize: 40),
    shapes: ThemeShapeStyle(
      stroke: Stroke(color: const SlideColor.theme(ThemeColor.text), width: 6),
      line: Stroke(color: const SlideColor.theme(ThemeColor.text), width: 6),
    ),
  );

  /// Every built-in theme, in picker order.
  static final all = List<SlideTheme>.unmodifiable(
    [light, dark, warm, cool, highContrast],
  );

  /// The built-in theme with [id], or `null` when there is none.
  static SlideTheme? byId(String id) {
    for (final theme in all) {
      if (theme.id == id) return theme;
    }
    return null;
  }
}
