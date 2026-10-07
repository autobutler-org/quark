import '../format/qslide_format_exception.dart';
import '../format/json_fields.dart';

/// The size of every slide in a presentation, in slide units.
///
/// Slide units are an abstract coordinate space: element frames are placed
/// in it and a renderer scales it to whatever surface it draws on, so only
/// the ratio of [width] to [height] reaches the screen. The presets use
/// 1920×1080 and 1024×768 so that one unit is roughly one pixel at full
/// HD.
class SlideSize {
  /// Creates a slide size; both dimensions must be positive.
  SlideSize({required this.width, required this.height, this.extra = const {}})
      : assert(width > 0 && height > 0, 'a slide size must be positive');

  /// A 16:9 slide, 1920×1080 units. The default for new presentations.
  static final widescreen = SlideSize(width: 1920, height: 1080);

  /// A 4:3 slide, 1024×768 units.
  static final standard = SlideSize(width: 1024, height: 768);

  /// Width in slide units.
  final double width;

  /// Height in slide units.
  final double height;

  /// Fields a newer writer added that this version does not read, kept so
  /// they survive a save.
  final JsonMap extra;

  /// [width] divided by [height].
  double get aspectRatio => width / height;

  static const _known = {'width', 'height'};

  /// Reads a size from its `.qslide` object at [path].
  factory SlideSize.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final width = requireNumber(json, 'width', path);
    final height = requireNumber(json, 'height', path);
    if (width <= 0 || height <= 0) {
      throw QslideFormatException('a slide size must be positive', path: path);
    }
    return SlideSize(
      width: width,
      height: height,
      extra: unknownFields(json, _known),
    );
  }

  /// The size as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'width': jsonNumber(width),
        'height': jsonNumber(height),
      };

  @override
  bool operator ==(Object other) =>
      other is SlideSize &&
      other.width == width &&
      other.height == height &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(width, height, jsonHash(extra));

  @override
  String toString() => 'SlideSize($width×$height)';
}
