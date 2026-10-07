import '../format/qslide_format_exception.dart';

/// A color in a presentation, stored as a 32-bit ARGB value.
///
/// It is written to `.qslide` as CSS-style hex: `#RRGGBB` when opaque and
/// `#RRGGBBAA` otherwise. The package keeps its own color type rather than
/// Flutter's `Color` so the model stays plain Dart.
///
/// ```dart
/// const red = SlideColor(0xFFFF0000);
/// SlideColor.parse('#FF000080'); // half-transparent red
/// ```
class SlideColor {
  /// Creates a color from an `0xAARRGGBB` value.
  const SlideColor(this.argb);

  /// Opaque white.
  static const white = SlideColor(0xFFFFFFFF);

  /// Opaque black.
  static const black = SlideColor(0xFF000000);

  /// The color as `0xAARRGGBB`.
  final int argb;

  /// Parses `#RRGGBB` or `#RRGGBBAA`; [path] locates the value in error
  /// messages.
  factory SlideColor.parse(String hex, {String path = r'$'}) {
    final match =
        RegExp(r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$').firstMatch(hex);
    if (match == null) {
      throw QslideFormatException('expected #RRGGBB or #RRGGBBAA', path: path);
    }
    final rgb = int.parse(match[1]!, radix: 16);
    final alpha = match[2] == null ? 0xFF : int.parse(match[2]!, radix: 16);
    return SlideColor((alpha << 24) | rgb);
  }

  /// The color in `.qslide` hex form.
  String toHex() {
    String byte(int shift) =>
        ((argb >> shift) & 0xFF).toRadixString(16).padLeft(2, '0');
    final rgb = '#${byte(16)}${byte(8)}${byte(0)}'.toUpperCase();
    return argb >>> 24 == 0xFF ? rgb : '$rgb${byte(24).toUpperCase()}';
  }

  @override
  bool operator ==(Object other) => other is SlideColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() => 'SlideColor(${toHex()})';
}
