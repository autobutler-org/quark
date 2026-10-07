import 'package:flutter/rendering.dart';

import '../model/slide_element.dart';
import '../model/stroke.dart';
import 'slide_shape_paths.dart';

/// Paints a [LineElement] across the diagonal of the box it is given — the
/// element's frame, in slide units — dashed as its [Stroke.dash] says, with
/// an arrowhead at each end that asks for one. A capped end stops short
/// under its arrowhead, so a wide stroke does not poke past the point.
class SlideLinePainter extends CustomPainter {
  /// Creates a painter for [line].
  const SlideLinePainter(this.line);

  /// The line to paint.
  final LineElement line;

  @override
  void paint(Canvas canvas, Size size) {
    final width = line.stroke.width;
    if (width <= 0) return;
    final (start, end) = lineEnds(size, flipped: line.flipped);
    final startArrow = line.startCap == LineCap.arrow;
    final endArrow = line.endCap == LineCap.arrow;
    final color = Color(line.stroke.color.argb);
    final length = (end - start).distance;
    final inset = arrowheadLength(width) / 2;
    final unit = length == 0 ? Offset.zero : (end - start) / length;
    final from = start + unit * (startArrow ? inset : 0);
    final to = end - unit * (endArrow ? inset : 0);
    final segment = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
    final intervals = dashIntervals(line.stroke.dash, width);
    canvas.drawPath(
      intervals == null ? segment : dashedPath(segment, intervals),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = width
        ..strokeCap = intervals == null ? StrokeCap.round : StrokeCap.butt,
    );
    final fill = Paint()..color = color;
    if (startArrow) canvas.drawPath(arrowheadPath(end, start, width), fill);
    if (endArrow) canvas.drawPath(arrowheadPath(start, end, width), fill);
  }

  @override
  bool shouldRepaint(SlideLinePainter oldDelegate) => oldDelegate.line != line;
}
