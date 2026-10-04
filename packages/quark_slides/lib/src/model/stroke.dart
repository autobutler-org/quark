import '../format/json_fields.dart';
import 'slide_color.dart';

/// The pattern a [Stroke] is drawn in.
///
/// In `.qslide` it is the stroke's `dash` field, left out when [solid]. A
/// value this version does not know — a name a newer writer added, or a
/// custom pattern written as an array — draws as [solid] and is kept
/// verbatim, so saving the file again does not lose it.
enum StrokeDash {
  /// A continuous line.
  solid,

  /// Dashes three stroke widths long with one-width gaps.
  dash,

  /// Round dots one stroke width apart.
  dot,

  /// Alternating dashes and dots.
  dashDot,
}

/// The outline drawn along a shape's edge or along a line.
class Stroke {
  /// Creates a stroke; [width] is in slide units and must not be negative.
  Stroke({
    this.color = SlideColor.black,
    this.width = 2,
    this.dash = StrokeDash.solid,
    this.extra = const {},
  }) : assert(width >= 0, 'a stroke width cannot be negative');

  /// The stroke color.
  final SlideColor color;

  /// The stroke width in slide units.
  final double width;

  /// The pattern the stroke is drawn in.
  final StrokeDash dash;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {'color', 'width', 'dash'};

  /// Reads a stroke from its `.qslide` object at [path].
  factory Stroke.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final color = optionalString(json, 'color', path);
    final dash = StrokeDash.values.asNameMap()[json['dash']];
    return Stroke(
      color: color == null
          ? SlideColor.black
          : SlideColor.parse(color, path: '$path.color'),
      width: optionalNumber(json, 'width', path) ?? 2,
      dash: dash ?? StrokeDash.solid,
      // A dash this version cannot read stays in extra and is written back.
      extra: unknownFields(
        json,
        dash == null && json.containsKey('dash')
            ? _known.difference(const {'dash'})
            : _known,
      ),
    );
  }

  /// The stroke as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'color': color.toHex(),
        'width': jsonNumber(width),
        if (dash != StrokeDash.solid) 'dash': dash.name,
      };

  /// Returns a copy with the given fields replaced.
  Stroke copyWith({SlideColor? color, double? width, StrokeDash? dash}) =>
      Stroke(
        color: color ?? this.color,
        width: width ?? this.width,
        dash: dash ?? this.dash,
        // A chosen dash replaces whatever unreadable one was kept.
        extra:
            dash == null ? extra : Map.unmodifiable({...extra}..remove('dash')),
      );

  @override
  bool operator ==(Object other) =>
      other is Stroke &&
      other.color == color &&
      other.width == width &&
      other.dash == dash &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(color, width, dash, jsonHash(extra));
}
