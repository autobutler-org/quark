import '../format/json_fields.dart';
import 'slide_background.dart';
import 'slide_element.dart';
import 'slide_transition_spec.dart';
import 'unset.dart';
import '../layout/slide_layout.dart';

/// One slide: a [background], the [elements] drawn on it, the speaker
/// [notes], the [layoutId] of the `SlideLayout` it is built on, and the
/// [transition] it comes onto the screen with when presenting.
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
    this.layoutId = SlideLayout.blankId,
    this.transition,
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

  /// The id of the slide's layout in `SlideMaster.standard`;
  /// [SlideLayout.blankId] by default. An id this version does not know is
  /// kept, and the slide is treated as having no placeholder slots.
  final String layoutId;

  /// The slide's own transition, played as the show arrives at it, or
  /// `null` to follow `Presentation.defaultTransition`. Read the one that
  /// plays with `Presentation.transitionFor`.
  final SlideTransitionSpec? transition;

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

  static const _known = {
    'id',
    'background',
    'elements',
    'notes',
    'layout',
    'transition',
  };

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
      layoutId: optionalString(json, 'layout', path) ?? SlideLayout.blankId,
      transition: json['transition'] == null
          ? null
          : SlideTransitionSpec.fromJson(
              json['transition'],
              '$path.transition',
            ),
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
        if (layoutId != SlideLayout.blankId) 'layout': layoutId,
        if (transition != null) 'transition': transition!.toJson(),
      };

  /// Returns a copy with the given fields replaced; pass `null` as
  /// [background] to fall back to the theme's, and as [transition] to
  /// follow the deck's.
  Slide copyWith({
    String? id,
    Object? background = unset,
    List<SlideElement>? elements,
    String? notes,
    String? layoutId,
    Object? transition = unset,
  }) =>
      Slide(
        id: id ?? this.id,
        background: identical(background, unset)
            ? this.background
            : background as SlideBackground?,
        elements:
            elements == null ? this.elements : List.unmodifiable(elements),
        notes: notes ?? this.notes,
        layoutId: layoutId ?? this.layoutId,
        transition: identical(transition, unset)
            ? this.transition
            : transition as SlideTransitionSpec?,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is Slide &&
      other.id == id &&
      other.background == background &&
      other.notes == notes &&
      other.layoutId == layoutId &&
      other.transition == transition &&
      listEquals(other.elements, elements) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        id,
        background,
        Object.hashAll(elements),
        notes,
        layoutId,
        transition,
        jsonHash(extra),
      );

  @override
  String toString() => 'Slide($id, ${elements.length} elements)';
}
