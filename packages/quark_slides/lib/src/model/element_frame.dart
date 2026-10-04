import '../format/qslide_format_exception.dart';
import '../format/json_fields.dart';

/// Where an element sits on its slide: an axis-aligned box in slide units,
/// rotated about its center.
///
/// [x] and [y] are the top-left corner of the box before rotation, measured from
/// the slide's top-left corner. [rotation] is in degrees, clockwise.
/// Stacking order is not part of the frame: it is the element's position in
/// `Slide.elements`, first at the back.
class ElementFrame {
  /// Creates a frame; [width] and [height] must not be negative.
  ElementFrame({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.extra = const {},
  }) : assert(width >= 0 && height >= 0, 'a frame cannot be negative');

  /// Left edge of the box before rotation, in slide units.
  final double x;

  /// Top edge of the box before rotation, in slide units.
  final double y;

  /// Width in slide units.
  final double width;

  /// Height in slide units.
  final double height;

  /// Clockwise rotation about the center, in degrees.
  final double rotation;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {'x', 'y', 'width', 'height', 'rotation'};

  /// Reads a frame from its `.qslide` object at [path].
  factory ElementFrame.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final width = requireNumber(json, 'width', path);
    final height = requireNumber(json, 'height', path);
    if (width < 0 || height < 0) {
      throw QslideFormatException('a frame cannot be negative', path: path);
    }
    return ElementFrame(
      x: requireNumber(json, 'x', path),
      y: requireNumber(json, 'y', path),
      width: width,
      height: height,
      rotation: optionalNumber(json, 'rotation', path) ?? 0,
      extra: unknownFields(json, _known),
    );
  }

  /// The frame as its `.qslide` object; a zero rotation is omitted.
  JsonMap toJson() => {
        ...extra,
        'x': jsonNumber(x),
        'y': jsonNumber(y),
        'width': jsonNumber(width),
        'height': jsonNumber(height),
        if (rotation != 0) 'rotation': jsonNumber(rotation),
      };

  /// Returns a copy with the given fields replaced.
  ElementFrame copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
  }) =>
      ElementFrame(
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        extra: extra,
      );

  /// Returns a copy moved by [dx], [dy].
  ElementFrame translate(double dx, double dy) =>
      copyWith(x: x + dx, y: y + dy);

  @override
  bool operator ==(Object other) =>
      other is ElementFrame &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.rotation == rotation &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(x, y, width, height, rotation, jsonHash(extra));

  @override
  String toString() => 'ElementFrame($x, $y, $width×$height'
      '${rotation == 0 ? '' : ', $rotation°'})';
}
