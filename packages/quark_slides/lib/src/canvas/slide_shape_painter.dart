import 'package:flutter/rendering.dart';

import '../model/slide_element.dart';
import '../model/stroke.dart';
import '../theme/slide_theme.dart';
import 'slide_shape_paths.dart';

/// Paints a [ShapeElement]'s figure, fill and outline, fitted to the box it
/// is given — the element's frame, in slide units. The outline is dashed as
/// its [Stroke.dash] says; the shape's opacity is applied around the
/// painter, so a fill and an outline that overlap do not darken.
class SlideShapePainter extends CustomPainter {
  /// Creates a painter for [shape].
  const SlideShapePainter(this.shape, this.theme);

  /// The shape to paint.
  final ShapeElement shape;

  /// The theme a role color resolves against.
  final SlideTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final path = shapePath(
      shape.kind,
      Offset.zero & size,
      cornerRadius: shape.cornerRadius,
    );
    final fill = shape.fill;
    if (fill != null) {
      canvas.drawPath(path, Paint()..color = Color(fill.resolve(theme)));
    }
    final stroke = shape.stroke;
    if (stroke != null && stroke.width > 0) {
      final intervals = dashIntervals(stroke.dash, stroke.width);
      canvas.drawPath(
        intervals == null ? path : dashedPath(path, intervals),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width
          ..strokeJoin = StrokeJoin.miter
          ..color = Color(stroke.color.resolve(theme)),
      );
    }
  }

  @override
  bool shouldRepaint(SlideShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.theme != theme;
}
