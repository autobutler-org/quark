import '../format/json_fields.dart';
import '../model/slide_color.dart';
import '../model/stroke.dart';
import '../model/unset.dart';
import 'theme_color.dart';

/// How a `SlideTheme` styles the shapes and lines a user inserts: a shape's
/// [fill] and [stroke], and a line's [line] stroke.
///
/// Insertion copies these onto the new element, so they are its own from
/// then on; a theme color among them still follows the theme.
class ThemeShapeStyle {
  /// Creates a shape style.
  ThemeShapeStyle({
    this.fill = const SlideColor.theme(ThemeColor.accent1),
    this.stroke,
    Stroke? line,
    this.extra = const {},
  }) : line = line ??
            Stroke(color: const SlideColor.theme(ThemeColor.text), width: 4);

  /// A new shape's fill, or `null` for hollow.
  final SlideColor? fill;

  /// A new shape's outline, or `null` for none.
  final Stroke? stroke;

  /// A new line's stroke.
  final Stroke line;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {'fill', 'stroke', 'line'};

  /// Reads a shape style from its `.qslide` object at [path].
  factory ThemeShapeStyle.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final fill = optionalString(json, 'fill', path);
    return ThemeShapeStyle(
      fill: fill == null ? null : SlideColor.parse(fill, path: '$path.fill'),
      stroke: json['stroke'] == null
          ? null
          : Stroke.fromJson(json['stroke'], '$path.stroke'),
      line: json['line'] == null
          ? null
          : Stroke.fromJson(json['line'], '$path.line'),
      extra: unknownFields(json, _known),
    );
  }

  /// The shape style as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        if (fill != null) 'fill': fill!.toHex(),
        if (stroke != null) 'stroke': stroke!.toJson(),
        'line': line.toJson(),
      };

  /// Returns a copy with the given fields replaced; pass `null` to clear
  /// [fill] or [stroke].
  ThemeShapeStyle copyWith({
    Object? fill = unset,
    Object? stroke = unset,
    Stroke? line,
  }) =>
      ThemeShapeStyle(
        fill: identical(fill, unset) ? this.fill : fill as SlideColor?,
        stroke: identical(stroke, unset) ? this.stroke : stroke as Stroke?,
        line: line ?? this.line,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is ThemeShapeStyle &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.line == line &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(fill, stroke, line, jsonHash(extra));
}
