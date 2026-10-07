import '../format/json_fields.dart';
import '../model/slide_color.dart';
import 'theme_color.dart';

/// The size and color a `SlideTheme` gives one kind of text — a
/// title, a subtitle or body text — and whether it is set in the theme's
/// heading font or its body font.
///
/// A text run that leaves its size, family or color unset takes them from
/// the style of its box's `ThemeTextRole`.
class ThemeTextStyle {
  /// Creates a text style; [fontSize] is in slide units.
  const ThemeTextStyle({
    required this.fontSize,
    this.color = const SlideColor.theme(ThemeColor.text),
    this.heading = false,
    this.extra = const {},
  });

  /// The font size in slide units.
  final double fontSize;

  /// The text color, usually a theme role.
  final SlideColor color;

  /// Whether the text is set in the theme's heading font rather than its
  /// body font.
  final bool heading;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {'fontSize', 'color', 'heading'};

  /// Reads a text style from its `.qslide` object at [path].
  factory ThemeTextStyle.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final color = optionalString(json, 'color', path);
    return ThemeTextStyle(
      fontSize: requireNumber(json, 'fontSize', path),
      color: color == null
          ? const SlideColor.theme(ThemeColor.text)
          : SlideColor.parse(color, path: '$path.color'),
      heading: optionalBool(json, 'heading', path, false),
      extra: unknownFields(json, _known),
    );
  }

  /// The text style as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'fontSize': jsonNumber(fontSize),
        'color': color.toHex(),
        if (heading) 'heading': true,
      };

  /// Returns a copy with the given fields replaced.
  ThemeTextStyle copyWith({
    double? fontSize,
    SlideColor? color,
    bool? heading,
  }) =>
      ThemeTextStyle(
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        heading: heading ?? this.heading,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is ThemeTextStyle &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.heading == heading &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(fontSize, color, heading, jsonHash(extra));
}
