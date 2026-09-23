import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Paints one frame of `QuarkLoader`: a track circle and three orbit rings
/// tilted 60 degrees apart, each drawn as the ellipse its 3D spin projects to.
///
/// Stroke widths derive from the paint size (0.055 of it for the track, 0.045
/// for the rings), and every stroke sits inside the box.
class QuarkLoaderPainter extends CustomPainter {
  /// Creates a painter at [progress] through one spin, or with every ring held
  /// at 60 degrees when [progress] is null (the reduced-motion pose).
  const QuarkLoaderPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  /// How far through one spin the rings are, from 0 to 1, or null to hold
  /// them at a fixed 60-degree spin.
  final double? progress;

  /// The color of the three orbit rings.
  final Color ringColor;

  /// The color of the outer track circle.
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = size.shortestSide;
    final center = size.center(Offset.zero);
    final trackStroke = extent * 0.055;
    final ringStroke = extent * 0.045;

    canvas.drawCircle(
      center,
      (extent - trackStroke) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackStroke
        ..color = trackColor,
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringStroke
      ..color = ringColor;
    final radius = (extent - ringStroke) / 2;
    canvas.translate(center.dx, center.dy);
    for (var i = 0; i < 3; i++) {
      final spin = progress == null
          ? math.pi / 3
          : 2 * math.pi * (progress! + i / 3);
      canvas
        ..save()
        ..rotate(i * math.pi / 3)
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: 2 * radius * math.cos(spin).abs(),
            height: 2 * radius,
          ),
          ring,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(QuarkLoaderPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.trackColor != trackColor;
}
