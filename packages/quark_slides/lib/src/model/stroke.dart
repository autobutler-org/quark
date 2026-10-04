import '../format/json_fields.dart';
import 'slide_color.dart';

/// The outline drawn along a shape's edge or along a line.
class Stroke {
  /// Creates a stroke; [width] is in slide units and must not be negative.
  Stroke({
    this.color = SlideColor.black,
    this.width = 2,
    this.extra = const {},
  }) : assert(width >= 0, 'a stroke width cannot be negative');

  /// The stroke color.
  final SlideColor color;

  /// The stroke width in slide units.
  final double width;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {'color', 'width'};

  /// Reads a stroke from its `.qslide` object at [path].
  factory Stroke.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final color = optionalString(json, 'color', path);
    return Stroke(
      color: color == null
          ? SlideColor.black
          : SlideColor.parse(color, path: '$path.color'),
      width: optionalNumber(json, 'width', path) ?? 2,
      extra: unknownFields(json, _known),
    );
  }

  /// The stroke as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'color': color.toHex(),
        'width': jsonNumber(width),
      };

  @override
  bool operator ==(Object other) =>
      other is Stroke &&
      other.color == color &&
      other.width == width &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(color, width, jsonHash(extra));
}
