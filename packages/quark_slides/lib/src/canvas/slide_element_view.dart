import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/slide_element.dart';
import 'slide_canvas_style.dart';
import 'slide_image_source.dart';
import 'slide_line_painter.dart';
import 'slide_placeholder_view.dart';
import 'slide_shape_painter.dart';
import 'slide_text_box_view.dart';

/// One element drawn at its frame on a slide laid out in slide units: placed
/// in a `Stack`, sized, and rotated about its center.
///
/// The element's widget is keyed `slide_element_<id>`, so a test or a Probe
/// script can find it (`tap #slide_element_title`). It reads to a screen
/// reader as [label], marked [selected]; [onSelect], when given, is the
/// screen reader's tap action. Pointer input is not handled here: the canvas
/// hit tests the slide's geometry itself.
///
/// While a text box is being edited the canvas passes its [editor], which
/// takes the place of the box's view and speaks for itself to a screen
/// reader. [showPlaceholder] shows an empty text box's placeholder. A shape
/// or line is drawn at its opacity; an image reads as its alt text through
/// [label].
class SlideElementView extends StatelessWidget {
  /// Creates the view of [element].
  const SlideElementView({
    super.key,
    required this.element,
    required this.style,
    required this.label,
    this.imageBuilder,
    this.selected = false,
    this.onSelect,
    this.editor,
    this.showPlaceholder = false,
    this.excluded = false,
  });

  /// The element to draw.
  final SlideElement element;

  /// Supplies text defaults and the placeholder color.
  final SlideCanvasStyle style;

  /// What a screen reader announces.
  final String label;

  /// Draws an [ImageElement]'s picture; without one it is a placeholder.
  final SlideImageBuilder? imageBuilder;

  /// Whether the element is selected, for the screen reader.
  final bool selected;

  /// Selects the element from a screen reader, or `null` when it cannot be
  /// selected — on a read-only slide.
  final VoidCallback? onSelect;

  /// The in-place editor drawn instead of the element, or `null`.
  final Widget? editor;

  /// Whether an empty text box shows its placeholder.
  final bool showPlaceholder;

  /// Whether the view is left out of the semantics tree, as a drawing
  /// preview is.
  final bool excluded;

  /// The [ValueKey] value of the element with [id]: `slide_element_<id>`.
  static String keyName(String id) => 'slide_element_$id';

  static const _fits = {
    ImageFit.contain: BoxFit.contain,
    ImageFit.cover: BoxFit.cover,
    ImageFit.fill: BoxFit.fill,
  };

  @override
  Widget build(BuildContext context) {
    final frame = element.frame;
    final editor = this.editor;
    final Widget content = switch (element) {
      TextBox() when editor != null => editor,
      final TextBox box => SlideTextBoxView(
          box: box,
          style: style,
          showPlaceholder: showPlaceholder,
        ),
      final ShapeElement shape =>
        CustomPaint(painter: SlideShapePainter(shape), size: Size.infinite),
      final LineElement line =>
        CustomPaint(painter: SlideLinePainter(line), size: Size.infinite),
      ImageElement(:final source, :final fit) when imageBuilder != null =>
        ClipRect(
          child: imageBuilder!(
            context,
            SlideImageSource(source, fit: _fits[fit]!),
          ),
        ),
      ImageElement() || UnknownElement() => SlidePlaceholderView(style: style),
    };
    final opacity = switch (element) {
      ShapeElement(:final opacity) || LineElement(:final opacity) => opacity,
      _ => 1.0,
    };
    final drawn =
        opacity < 1 ? Opacity(opacity: opacity, child: content) : content;
    return Positioned(
      left: frame.x,
      top: frame.y,
      width: frame.width,
      height: frame.height,
      child: Transform.rotate(
        key: ValueKey(keyName(element.id)),
        angle: frame.rotation * math.pi / 180,
        child: excluded
            ? ExcludeSemantics(child: drawn)
            : editor != null
                ? drawn
                : Semantics(
                    container: true,
                    label: label,
                    selected: onSelect == null ? null : selected,
                    onTap: onSelect,
                    excludeSemantics: true,
                    child: drawn,
                  ),
      ),
    );
  }
}
