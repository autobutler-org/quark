import '../format/qslide_format_exception.dart';
import '../theme/slide_theme.dart';
import '../theme/theme_color.dart';

/// A color in a presentation: a literal 32-bit ARGB value, or a [role] in
/// the presentation's theme that is looked up when the slide is drawn.
///
/// A role color follows the theme: switching the deck from light to dark
/// recolors every fill, line and run that names one, while a literal color
/// stays as it is. [resolve] gives the value to paint.
///
/// It is written to `.qslide` as CSS-style hex — `#RRGGBB` when opaque and
/// `#RRGGBBAA` otherwise — or as `theme:<role>`. The package keeps its own
/// color type rather than Flutter's `Color` so the model stays plain Dart.
///
/// ```dart
/// const red = SlideColor(0xFFFF0000);
/// SlideColor.parse('#FF000080'); // half-transparent red
/// const accent = SlideColor.theme(ThemeColor.accent1);
/// accent.resolve(SlideThemes.dark); // the dark theme's first accent
/// ```
class SlideColor {
  /// Creates a literal color from an `0xAARRGGBB` value.
  const SlideColor(int argb)
      : _argb = argb,
        role = null;

  /// Creates a color that is [role] in whatever theme the deck uses.
  const SlideColor.theme(ThemeColor this.role) : _argb = 0;

  /// Opaque white.
  static const white = SlideColor(0xFFFFFFFF);

  /// Opaque black.
  static const black = SlideColor(0xFF000000);

  final int _argb;

  /// The theme role this color names, or `null` for a literal color.
  final ThemeColor? role;

  /// Whether this color names a theme role.
  bool get isThemeColor => role != null;

  /// The color as `0xAARRGGBB`: the literal value, or for a role color its
  /// [ThemeColor.fallback]. Paint with [resolve] instead, which honors the
  /// deck's theme.
  int get argb => role?.fallback ?? _argb;

  /// The color to paint in [theme], `0xAARRGGBB`: the literal value, or
  /// [role]'s color in [theme] — its fallback when [theme] is `null`.
  int resolve(SlideTheme? theme) =>
      role == null || theme == null ? argb : theme.colors[role!];

  static const _rolePrefix = 'theme:';

  /// Parses `#RRGGBB`, `#RRGGBBAA` or `theme:<role>`; [path] locates the
  /// value in error messages. A role this version does not know reads as
  /// [ThemeColor.text].
  factory SlideColor.parse(String hex, {String path = r'$'}) {
    if (hex.startsWith(_rolePrefix)) {
      final name = hex.substring(_rolePrefix.length);
      return SlideColor.theme(
        ThemeColor.values.asNameMap()[name] ?? ThemeColor.text,
      );
    }
    final match =
        RegExp(r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$').firstMatch(hex);
    if (match == null) {
      throw QslideFormatException(
        'expected #RRGGBB, #RRGGBBAA or theme:<role>',
        path: path,
      );
    }
    final rgb = int.parse(match[1]!, radix: 16);
    final alpha = match[2] == null ? 0xFF : int.parse(match[2]!, radix: 16);
    return SlideColor((alpha << 24) | rgb);
  }

  /// The color in `.qslide` form: hex, or `theme:<role>`.
  String toHex() {
    if (role case final role?) return '$_rolePrefix${role.name}';
    String byte(int shift) =>
        ((argb >> shift) & 0xFF).toRadixString(16).padLeft(2, '0');
    final rgb = '#${byte(16)}${byte(8)}${byte(0)}'.toUpperCase();
    return argb >>> 24 == 0xFF ? rgb : '$rgb${byte(24).toUpperCase()}';
  }

  @override
  bool operator ==(Object other) =>
      other is SlideColor && other.role == role && other._argb == _argb;

  @override
  int get hashCode => Object.hash(role, _argb);

  @override
  String toString() => 'SlideColor(${toHex()})';
}
