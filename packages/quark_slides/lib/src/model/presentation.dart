import '../format/json_fields.dart';
import 'slide.dart';
import 'slide_size.dart';
import 'unset.dart';

/// A whole presentation: its [title], the [size] every slide shares, the
/// [theme] it is styled with, and its [slides] in show order.
///
/// Presentations are immutable; every edit produces a new one, which is
/// what makes undo a matter of keeping the old one. Read and write them as
/// `.qslide` with `QslideCodec`.
///
/// ```dart
/// final deck = Presentation(
///   title: 'Quarterly review',
///   slides: [Slide(id: 's1')],
/// );
/// ```
class Presentation {
  /// Creates a presentation; [size] defaults to [SlideSize.widescreen].
  Presentation({
    this.title = '',
    SlideSize? size,
    this.theme,
    List<Slide> slides = const [],
    this.extra = const {},
  })  : size = size ?? SlideSize.widescreen,
        slides = List.unmodifiable(slides);

  /// The presentation's title, shown in file listings and the window.
  final String title;

  /// The size of every slide.
  final SlideSize size;

  /// A reference to the theme — its id or file path — or `null` for the
  /// default theme. Themes themselves are not part of this model yet.
  final String? theme;

  /// The slides, in show order.
  final List<Slide> slides;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  /// The index of the slide with [slideId] in [slides], or -1.
  int indexOfSlide(String slideId) => slides.indexWhere((s) => s.id == slideId);

  /// The slide with [slideId], or `null` when there is none.
  Slide? slideById(String slideId) {
    final index = indexOfSlide(slideId);
    return index < 0 ? null : slides[index];
  }

  static const _known = {'schemaVersion', 'title', 'size', 'theme', 'slides'};

  /// Reads the presentation fields of a `.qslide` root object at [path].
  /// `QslideCodec.decode` checks `schemaVersion` before calling this.
  factory Presentation.fromJson(Object? value, [String path = r'$']) {
    final json = asObject(value, path);
    final slides = optionalList(json, 'slides', path);
    return Presentation(
      title: optionalString(json, 'title', path) ?? '',
      size: json['size'] == null
          ? null
          : SlideSize.fromJson(json['size'], '$path.size'),
      theme: optionalString(json, 'theme', path),
      slides: [
        for (var i = 0; i < slides.length; i++)
          Slide.fromJson(slides[i], '$path.slides[$i]'),
      ],
      extra: unknownFields(json, _known),
    );
  }

  /// The presentation fields of a `.qslide` root object, without
  /// `schemaVersion`; `QslideCodec.encode` adds it.
  JsonMap toJson() => {
        ...extra,
        'title': title,
        'size': size.toJson(),
        if (theme != null) 'theme': theme,
        'slides': [for (final s in slides) s.toJson()],
      };

  /// Returns a copy with the given fields replaced; pass `null` as [theme]
  /// to use the default theme.
  Presentation copyWith({
    String? title,
    SlideSize? size,
    Object? theme = unset,
    List<Slide>? slides,
  }) =>
      Presentation(
        title: title ?? this.title,
        size: size ?? this.size,
        theme: identical(theme, unset) ? this.theme : theme as String?,
        slides: slides ?? this.slides,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is Presentation &&
      other.title == title &&
      other.size == size &&
      other.theme == theme &&
      listEquals(other.slides, slides) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(title, size, theme, Object.hashAll(slides), jsonHash(extra));

  @override
  String toString() => 'Presentation($title, ${slides.length} slides)';
}
