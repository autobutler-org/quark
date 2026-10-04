import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../model/slide_element.dart';

/// Paints a [ShapeElement]'s figure, fill and outline, fitted to the box it
/// is given — the element's frame, in slide units.
class SlideShapePainter extends CustomPainter {
  /// Creates a painter for [shape].
  const SlideShapePainter(this.shape);

  /// The shape to paint.
  final ShapeElement shape;

  @override
  void paint(Canvas canvas, Size size) {
    final path = shapePath(shape.kind, Offset.zero & size);
    final fill = shape.fill;
    if (fill != null) {
      canvas.drawPath(path, Paint()..color = Color(fill.argb));
    }
    final stroke = shape.stroke;
    if (stroke != null && stroke.width > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width
          ..strokeJoin = StrokeJoin.miter
          ..color = Color(stroke.color.argb),
      );
    }
  }

  @override
  bool shouldRepaint(SlideShapePainter oldDelegate) =>
      oldDelegate.shape != shape;
}

/// The outline of a [kind] of shape fitted to [box].
Path shapePath(ShapeKind kind, Rect box) {
  final w = box.width;
  final h = box.height;
  Offset at(double fx, double fy) => box.topLeft + Offset(w * fx, h * fy);
  Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
  switch (kind) {
    case ShapeKind.rectangle:
      return Path()..addRect(box);
    case ShapeKind.roundedRectangle:
      final radius = Radius.circular(math.min(w, h) * 0.15);
      return Path()..addRRect(RRect.fromRectAndRadius(box, radius));
    case ShapeKind.ellipse:
      return Path()..addOval(box);
    case ShapeKind.triangle:
      return polygon([at(0.5, 0), at(1, 1), at(0, 1)]);
    case ShapeKind.diamond:
      return polygon([at(0.5, 0), at(1, 0.5), at(0.5, 1), at(0, 0.5)]);
    case ShapeKind.arrow:
      return polygon([
        at(0, 0.3),
        at(0.6, 0.3),
        at(0.6, 0),
        at(1, 0.5),
        at(0.6, 1),
        at(0.6, 0.7),
        at(0, 0.7),
      ]);
    case ShapeKind.star:
      return polygon([
        for (var i = 0; i < 10; i++)
          at(
            0.5 + (i.isEven ? 0.5 : 0.2) * math.sin(i * math.pi / 5),
            0.5 - (i.isEven ? 0.5 : 0.2) * math.cos(i * math.pi / 5),
          ),
      ]);
  }
}
