import '../format/json_fields.dart';
import 'slide_color.dart';
import 'unset.dart';

/// What a slide is painted with behind its elements: a solid [color], an
/// [image], or both, with the image drawn over the color.
///
/// A slide whose background is `null` uses the presentation theme's.
class SlideBackground {
  /// Creates a background.
  const SlideBackground({this.color, this.image, this.extra = const {}});

  /// The fill color, or `null` for none.
  final SlideColor? color;

  /// An opaque reference to an image — a file path or URL the host app
  /// resolves — drawn to cover the slide, or `null` for none.
  final String? image;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {'color', 'image'};

  /// Reads a background from its `.qslide` object at [path].
  factory SlideBackground.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final color = optionalString(json, 'color', path);
    return SlideBackground(
      color:
          color == null ? null : SlideColor.parse(color, path: '$path.color'),
      image: optionalString(json, 'image', path),
      extra: unknownFields(json, _known),
    );
  }

  /// The background as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        if (color != null) 'color': color!.toHex(),
        if (image != null) 'image': image,
      };

  /// Returns a copy with the given fields replaced; pass `null` to clear one.
  SlideBackground copyWith({Object? color = unset, Object? image = unset}) =>
      SlideBackground(
        color: identical(color, unset) ? this.color : color as SlideColor?,
        image: identical(image, unset) ? this.image : image as String?,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is SlideBackground &&
      other.color == color &&
      other.image == image &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(color, image, jsonHash(extra));
}
