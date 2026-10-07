import '../model/slide_element.dart';
import 'slide_canvas_tool.dart';

/// Names a drawing tool for a screen reader, as the action of inserting
/// with it.
///
/// `SlideCanvas` takes one of these so an app can localize the labels; the
/// default is [defaultSlideToolLabel]. A toolbar can use the same function
/// for its buttons' tooltips.
typedef SlideToolLabel = String Function(SlideCanvasTool tool);

/// English labels: "Insert text box", "Insert star", "Insert arrow", and
/// "Select" for the select tool.
///
/// ```dart
/// defaultSlideToolLabel(const SlideCanvasTool.shape(ShapeKind.ellipse));
/// // 'Insert ellipse'
/// ```
String defaultSlideToolLabel(SlideCanvasTool tool) => switch (tool.mode) {
      SlideToolMode.select => 'Select',
      SlideToolMode.text => 'Insert text box',
      SlideToolMode.shape => 'Insert ${shapeKindName(tool.shapeKind!)}',
      SlideToolMode.line => tool.arrow ? 'Insert arrow' : 'Insert line',
      SlideToolMode.image => 'Insert image',
    };

/// The English name of a [kind] of shape, lowercase: "rounded rectangle",
/// "right arrow".
String shapeKindName(ShapeKind kind) => switch (kind) {
      ShapeKind.rectangle => 'rectangle',
      ShapeKind.roundedRectangle => 'rounded rectangle',
      ShapeKind.ellipse => 'ellipse',
      ShapeKind.triangle => 'triangle',
      ShapeKind.diamond => 'diamond',
      ShapeKind.arrow => 'right arrow',
      ShapeKind.star => 'star',
    };
