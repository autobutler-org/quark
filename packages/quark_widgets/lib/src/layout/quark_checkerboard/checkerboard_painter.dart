import 'package:flutter/material.dart';

/// Paints the alternating squares behind `QuarkCheckerboard`'s child.
///
/// Split out because a `CustomPainter` is not a widget and has no place in the
/// widget's own file. Not exported from the barrel — nothing outside
/// `QuarkCheckerboard` needs it yet.
class CheckerboardPainter extends CustomPainter {
  /// Creates a painter drawing [squareSize] squares in [light] and [dark].
  const CheckerboardPainter({
    required this.light,
    required this.dark,
    required this.squareSize,
  });

  /// The color of the base fill and of every even square.
  final Color light;

  /// The color of the odd squares, drawn on top of the [light] fill.
  final Color dark;

  /// The edge length of one square in logical pixels.
  final double squareSize;

  @override
  void paint(Canvas canvas, Size size) {
    // CustomPaint does not clip, and the last row and column are partial
    // squares, so without this the board bleeds past the widget it backs.
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = light);

    final paint = Paint()..color = dark;
    final columns = (size.width / squareSize).ceil();
    final rows = (size.height / squareSize).ceil();
    for (var row = 0; row < rows; row++) {
      for (var column = row.isEven ? 1 : 0; column < columns; column += 2) {
        canvas.drawRect(
          Offset(column * squareSize, row * squareSize) &
              Size.square(squareSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter oldDelegate) =>
      oldDelegate.light != light ||
      oldDelegate.dark != dark ||
      oldDelegate.squareSize != squareSize;
}
