import '../format/json_fields.dart';
import 'slide_background.dart';
import 'slide_element.dart';
import 'unset.dart';

/// One slide: a [background], the [elements] drawn on it, and the
/// speaker [notes].
///
/// [elements] is in stacking order, first at the back. [id] is unique
/// within the presentation and stays with the slide as it is reordered.
class Slide {
  /// Creates a slide.
  const Slide({
    required this.id,
    this.background,
    this.elements = const [],
    this.notes = '',
    this.extra = const {},
  });

  /// The slide's stable id.
  final String id;

  /// The slide's own background, or `null` to use the theme's.
  final SlideBackground? background;

  /// The elements on the slide, back to front.
  final List<SlideElement> elements;

  /// Speaker notes, plain text.
  final String notes;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  /// The index of the element with [elementId] in [elements], or -1.
  int indexOfElement(String elementId) =>
      elements.indexWhere((e) => e.id == elementId);

  /// The element with [elementId], or `null` when the slide has none.
  SlideElement? elementById(String elementId) {
    final index = indexOfElement(elementId);
    return index < 0 ? null : elements[index];
  }

  static const _known = {'id', 'background', 'elements', 'notes'};

  /// Reads a slide from its `.qslide` object at [path].
  factory Slide.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final elements = optionalList(json, 'elements', path);
    return Slide(
      id: requireString(json, 'id', path),
      background: json['background'] == null
          ? null
          : SlideBackground.fromJson(json['background'], '$path.background'),
      elements: List.unmodifiable([
        for (var i = 0; i < elements.length; i++)
          SlideElement.fromJson(elements[i], '$path.elements[$i]'),
      ]),
      notes: optionalString(json, 'notes', path) ?? '',
      extra: unknownFields(json, _known),
    );
  }

  /// The slide as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'id': id,
        if (background != null) 'background': background!.toJson(),
        'elements': [for (final e in elements) e.toJson()],
        if (notes.isNotEmpty) 'notes': notes,
      };

  /// Returns a copy with the given fields replaced; pass `null` as
  /// [background] to fall back to the theme's.
  Slide copyWith({
    String? id,
    Object? background = unset,
    List<SlideElement>? elements,
    String? notes,
  }) =>
      Slide(
        id: id ?? this.id,
        background: identical(background, unset)
            ? this.background
            : background as SlideBackground?,
        elements:
            elements == null ? this.elements : List.unmodifiable(elements),
        notes: notes ?? this.notes,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is Slide &&
      other.id == id &&
      other.background == background &&
      other.notes == notes &&
      listEquals(other.elements, elements) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        id,
        background,
        Object.hashAll(elements),
        notes,
        jsonHash(extra),
      );

  @override
  String toString() => 'Slide($id, ${elements.length} elements)';
}
