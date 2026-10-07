import 'slide_color.dart';
import 'slide_element.dart';
import 'stroke.dart';
import 'unset.dart';

/// A change to how shapes and lines are drawn, or a summary of what a
/// selection of them shares — the drawing counterpart of `TextFormat`.
///
/// **As a change** — what `SlideDocumentController.styleElements` takes —
/// a field left out leaves that property alone, and a field that does not
/// apply to an element is skipped: [fill], [cornerRadius] and [kind] are
/// shapes' only, the caps lines' only.
///
/// - [fill]: a [SlideColor] for a solid fill, `null` for none.
/// - [stroke]: a [Stroke] replaces a shape's outline and `null` removes it
///   (a line keeps its stroke).
/// - [strokeColor], [strokeWidth], [dash]: restyle the outline, giving a
///   shape without one a default [Stroke] first.
/// - [cornerRadius]: a `double` in slide units, or `null` for the
///   proportional default.
/// - [opacity]: 0 to 1, the whole element.
///
/// ```dart
/// const ElementStyle(fill: SlideColor(0xFF3366FF), opacity: 0.5);
/// const ElementStyle(fill: null, dash: StrokeDash.dash); // hollow, dashed
/// const ElementStyle(endCap: LineCap.arrow);
/// ```
///
/// **As a summary** — what [elementStyleOf] returns — each field holds the
/// value every element it applies to shares, and is left out where they
/// differ.
class ElementStyle {
  /// Creates a change or a summary; see the class doc.
  const ElementStyle({
    this.fill = unset,
    this.stroke = unset,
    this.strokeColor,
    this.strokeWidth,
    this.dash,
    this.cornerRadius = unset,
    this.opacity,
    this.kind,
    this.startCap,
    this.endCap,
  });

  /// A [SlideColor], `null` for no fill, or [unset].
  final Object? fill;

  /// A [Stroke] to replace a shape's outline, `null` to remove it, or
  /// [unset]. In a summary, `null` when no shape in the selection has an
  /// outline.
  final Object? stroke;

  /// The outline's color.
  final SlideColor? strokeColor;

  /// The outline's width in slide units.
  final double? strokeWidth;

  /// The outline's pattern.
  final StrokeDash? dash;

  /// A `double` radius in slide units, `null` for the default, or [unset].
  final Object? cornerRadius;

  /// The whole element's opacity, 0 to 1.
  final double? opacity;

  /// A shape's figure.
  final ShapeKind? kind;

  /// What a line draws at its start.
  final LineCap? startCap;

  /// What a line draws at its end.
  final LineCap? endCap;

  /// [element] with this change applied; any element other than a
  /// [ShapeElement] or [LineElement] comes back unchanged.
  SlideElement applyTo(SlideElement element) {
    switch (element) {
      case ShapeElement():
        Stroke? outline =
            identical(stroke, unset) ? element.stroke : stroke as Stroke?;
        if (strokeColor != null || strokeWidth != null || dash != null) {
          outline = (outline ?? Stroke()).copyWith(
            color: strokeColor,
            width: strokeWidth,
            dash: dash,
          );
        }
        return element.copyWith(
          kind: kind,
          fill: fill,
          stroke: outline,
          cornerRadius: cornerRadius,
          opacity: opacity,
        );
      case LineElement():
        return element.copyWith(
          stroke: element.stroke.copyWith(
            color: strokeColor,
            width: strokeWidth,
            dash: dash,
          ),
          startCap: startCap,
          endCap: endCap,
          opacity: opacity,
        );
      case TextBox() ||
            ImageElement() ||
            TableElement() ||
            ChartElement() ||
            GroupElement() ||
            UnknownElement():
        return element;
    }
  }
}

/// What the shapes and lines among [elements] share, as an [ElementStyle]
/// summary; a field none of them has, or they disagree on, is left out.
ElementStyle elementStyleOf(Iterable<SlideElement> elements) {
  final shapes = elements.whereType<ShapeElement>().toList();
  final lines = elements.whereType<LineElement>().toList();
  final strokes = [
    for (final s in shapes)
      if (s.stroke != null) s.stroke!,
    for (final l in lines) l.stroke,
  ];
  T? shared<T>(Iterable<T> values) {
    final distinct = values.toSet();
    return distinct.length == 1 ? distinct.single : null;
  }

  Object? sharedOrUnset(Iterable<Object?> values) {
    final distinct = values.toSet();
    return distinct.length == 1 ? distinct.single : unset;
  }

  return ElementStyle(
    fill: sharedOrUnset(shapes.map((s) => s.fill)),
    stroke: shapes.isNotEmpty && shapes.every((s) => s.stroke == null)
        ? null
        : unset,
    strokeColor: shared(strokes.map((s) => s.color)),
    strokeWidth: shared(strokes.map((s) => s.width)),
    dash: shared(strokes.map((s) => s.dash)),
    cornerRadius: sharedOrUnset(
      shapes
          .where((s) => s.kind == ShapeKind.roundedRectangle)
          .map((s) => s.cornerRadius),
    ),
    opacity: shared(
        [...shapes.map((s) => s.opacity), ...lines.map((l) => l.opacity)]),
    kind: shared(shapes.map((s) => s.kind)),
    startCap: shared(lines.map((l) => l.startCap)),
    endCap: shared(lines.map((l) => l.endCap)),
  );
}
