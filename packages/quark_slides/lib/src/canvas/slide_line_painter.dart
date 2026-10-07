import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../model/slide_element.dart';

/// Paints a [LineElement] across the diagonal of the box it is given — the
/// element's frame, in slide units — with an arrowhead at each end that
/// asks for one.
class SlideLinePainter extends CustomPainter {
  /// Creates a painter for [line].
  const SlideLinePainter(this.line);

  /// The line to paint.
  final LineElement line;

  @override
  void paint(Canvas canvas, Size size) {
    final width = line.stroke.width;
    if (width <= 0) return;
    final start = line.flipped ? Offset(0, size.height) : Offset.zero;
    final end =
        line.flipped ? Offset(size.width, 0) : size.bottomRight(Offset.zero);
    final color = Color(line.stroke.color.argb);
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    final fill = Paint()..color = color;
    if (line.startCap == LineCap.arrow) {
      _arrowhead(canvas, end, start, width, fill);
    }
    if (line.endCap == LineCap.arrow) {
      _arrowhead(canvas, start, end, width, fill);
    }
  }

  /// Draws an arrowhead at [tip], pointing away from [from].
  static void _arrowhead(
    Canvas canvas,
    Offset from,
    Offset tip,
    double strokeWidth,
    Paint paint,
  ) {
    final direction = tip - from;
    if (direction.distance == 0) return;
    final unit = direction / direction.distance;
    final length = math.max(12.0, strokeWidth * 4);
    final base = tip - unit * length;
    final side = Offset(-unit.dy, unit.dx) * (length / 2);
    canvas.drawPath(
      Path()..addPolygon([tip, base + side, base - side], true),
      paint,
    );
  }

  @override
  bool shouldRepaint(SlideLinePainter oldDelegate) => oldDelegate.line != line;
}
