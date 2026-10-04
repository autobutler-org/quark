import 'package:flutter/widgets.dart';

import 'slide_canvas_style.dart';

/// Stands in for content the canvas cannot draw — an image when no image
/// builder was given, or an element type this version does not know — as
/// an outlined box crossed corner to corner, so it can still be seen,
/// selected and moved.
class SlidePlaceholderView extends StatelessWidget {
  /// Creates a placeholder.
  const SlidePlaceholderView({super.key, required this.style});

  /// Supplies [SlideCanvasStyle.placeholderColor].
  final SlideCanvasStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _CrossedBoxPainter(style.placeholderColor),
        child: const SizedBox.expand(),
      );
}

class _CrossedBoxPainter extends CustomPainter {
  const _CrossedBoxPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas
      ..drawRect(Offset.zero & size, paint)
      ..drawLine(Offset.zero, size.bottomRight(Offset.zero), paint)
      ..drawLine(
          size.bottomLeft(Offset.zero), size.topRight(Offset.zero), paint);
  }

  @override
  bool shouldRepaint(_CrossedBoxPainter oldDelegate) =>
      oldDelegate.color != color;
}
