/// The paths behind shapes and lines, as pure functions of a box and a
/// style, so a painter is a few `drawPath` calls and each figure can be
/// tested as geometry.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../model/slide_element.dart';
import '../model/stroke.dart';

/// The outline of a [kind] of shape fitted to [box].
///
/// A [ShapeKind.roundedRectangle] rounds its corners by [cornerRadius], or
/// by 15% of the shorter side when that is `null`, never past half the
/// shorter side; other kinds ignore it.
///
/// ```dart
/// shapePath(ShapeKind.star, Offset.zero & const Size(100, 100));
/// ```
Path shapePath(ShapeKind kind, Rect box, {double? cornerRadius}) {
  final w = box.width;
  final h = box.height;
  Offset at(double fx, double fy) => box.topLeft + Offset(w * fx, h * fy);
  Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
  switch (kind) {
    case ShapeKind.rectangle:
      return Path()..addRect(box);
    case ShapeKind.roundedRectangle:
      final shorter = math.min(w, h);
      final radius = (cornerRadius ?? shorter * 0.15).clamp(0.0, shorter / 2);
      return Path()
        ..addRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)));
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
      return polygon(starPoints(box));
  }
}

/// The ten corners of a five-pointed star stretched to fill [box],
/// clockwise from the top point, alternating outer points and inner
/// corners; the inner corners sit at [innerRatio] of the outer radius.
List<Offset> starPoints(Rect box, {double innerRatio = 0.4}) {
  final unit = [
    for (var i = 0; i < 10; i++)
      Offset.fromDirection(
        i * math.pi / 5 - math.pi / 2,
        i.isEven ? 1 : innerRatio,
      ),
  ];
  // A regular star is narrower than its circle and stops short of its
  // bottom; stretch its own bounds to the box.
  var left = 0.0, right = 0.0, top = 0.0, bottom = 0.0;
  for (final p in unit) {
    left = math.min(left, p.dx);
    right = math.max(right, p.dx);
    top = math.min(top, p.dy);
    bottom = math.max(bottom, p.dy);
  }
  return [
    for (final p in unit)
      Offset(
        box.left + (p.dx - left) / (right - left) * box.width,
        box.top + (p.dy - top) / (bottom - top) * box.height,
      ),
  ];
}

/// The two ends of a line drawn across a box of [size] with its top-left
/// at the origin: top-left to bottom-right, or bottom-left to top-right
/// when [flipped].
(Offset, Offset) lineEnds(Size size, {bool flipped = false}) => flipped
    ? (Offset(0, size.height), Offset(size.width, 0))
    : (Offset.zero, size.bottomRight(Offset.zero));

/// How long an arrowhead on a line [strokeWidth] wide is, tip to base.
double arrowheadLength(double strokeWidth) => math.max(12.0, strokeWidth * 4);

/// A filled arrowhead with its point at [tip], pointing away from [from],
/// sized for a line [strokeWidth] wide: [arrowheadLength] long and half as
/// wide on each side. Empty when the two points coincide.
Path arrowheadPath(Offset from, Offset tip, double strokeWidth) {
  final direction = tip - from;
  if (direction.distance == 0) return Path();
  final unit = direction / direction.distance;
  final length = arrowheadLength(strokeWidth);
  final base = tip - unit * length;
  final side = Offset(-unit.dy, unit.dx) * (length / 2);
  return Path()..addPolygon([tip, base + side, base - side], true);
}

/// The on-off lengths, in slide units, that draw [dash] on a stroke
/// [strokeWidth] wide, or `null` for a solid stroke.
List<double>? dashIntervals(StrokeDash dash, double strokeWidth) {
  final w = math.max(strokeWidth, 1.0);
  return switch (dash) {
    StrokeDash.solid => null,
    StrokeDash.dash => [w * 3, w * 2],
    StrokeDash.dot => [w, w],
    StrokeDash.dashDot => [w * 3, w * 1.5, w, w * 1.5],
  };
}

/// [source] cut into dashes by [intervals] — alternating on and off
/// lengths, repeated along each contour from its start.
Path dashedPath(Path source, List<double> intervals) {
  assert(intervals.isNotEmpty && intervals.every((i) => i > 0));
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var index = 0;
    while (distance < metric.length) {
      final length = intervals[index % intervals.length];
      if (index.isEven) {
        dashed.addPath(
          metric.extractPath(
              distance, math.min(distance + length, metric.length)),
          Offset.zero,
        );
      }
      distance += length;
      index++;
    }
  }
  return dashed;
}
