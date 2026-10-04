import 'package:flutter/foundation.dart';

import '../model/slide_element.dart';

/// The kinds of thing a pointer can do on an editing `SlideCanvas`; the
/// [SlideCanvasTool.mode] of a tool.
enum SlideToolMode {
  /// Select, move, resize and rotate elements.
  select,

  /// Draw a text box.
  text,

  /// Draw a shape of [SlideCanvasTool.shapeKind].
  shape,

  /// Draw a line, or an arrow when [SlideCanvasTool.arrow].
  line,

  /// Choose where a picture goes; the app picks the picture.
  image,
}

/// What a pointer does on an editing `SlideCanvas`: a [mode], plus the kind
/// of shape for a shape tool and whether a line tool draws an arrow.
///
/// Every drawing tool works the same way: a click places the element at its
/// default size with its top-left corner at the pointer, and a drag draws
/// it — Shift keeps a shape square or turns a line to a multiple of 45°,
/// Alt draws out from the point pressed. Each insertion is one undo step,
/// and afterwards the canvas selects the new element and hands the tool
/// back to [select]. Escape hands it back without drawing.
///
/// ```dart
/// tools.use(SlideCanvasTool.select);
/// tools.use(SlideCanvasTool.text);
/// tools.use(const SlideCanvasTool.shape(ShapeKind.star));
/// tools.use(SlideCanvasTool.line);
/// tools.use(SlideCanvasTool.arrowLine);
/// tools.use(SlideCanvasTool.image);
/// ```
@immutable
final class SlideCanvasTool {
  const SlideCanvasTool._(this.mode, {this.shapeKind, this.arrow = false});

  /// Draws a [kind] of shape.
  const SlideCanvasTool.shape(ShapeKind kind)
      : this._(SlideToolMode.shape, shapeKind: kind);

  /// Selects, moves, resizes and rotates elements.
  static const select = SlideCanvasTool._(SlideToolMode.select);

  /// Draws a text box, which opens for typing; one left empty disappears.
  static const text = SlideCanvasTool._(SlideToolMode.text);

  /// Draws a plain line.
  static const line = SlideCanvasTool._(SlideToolMode.line);

  /// Draws a line with an arrowhead at the end the drag finishes on.
  static const arrowLine = SlideCanvasTool._(SlideToolMode.line, arrow: true);

  /// Marks where a picture goes — a click for the default place, a drag
  /// for a box to fit it in — and asks the app for one through
  /// `SlideCanvas.onPickImage`.
  static const image = SlideCanvasTool._(SlideToolMode.image);

  /// What the tool does.
  final SlideToolMode mode;

  /// The shape a [SlideToolMode.shape] tool draws; `null` for the others.
  final ShapeKind? shapeKind;

  /// Whether a [SlideToolMode.line] tool draws an arrow.
  final bool arrow;

  /// Whether the tool adds elements rather than selecting them.
  bool get draws => mode != SlideToolMode.select;

  @override
  bool operator ==(Object other) =>
      other is SlideCanvasTool &&
      other.mode == mode &&
      other.shapeKind == shapeKind &&
      other.arrow == arrow;

  @override
  int get hashCode => Object.hash(mode, shapeKind, arrow);

  @override
  String toString() => switch (mode) {
        SlideToolMode.shape => 'SlideCanvasTool.shape(${shapeKind!.name})',
        SlideToolMode.line when arrow => 'SlideCanvasTool.arrowLine',
        _ => 'SlideCanvasTool.${mode.name}',
      };
}
