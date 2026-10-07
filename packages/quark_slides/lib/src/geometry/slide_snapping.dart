import 'dart:ui';

import '../model/slide.dart';
import '../model/slide_size.dart';
import 'frame_geometry.dart';

/// Which way a [SnapGuide] runs.
enum SnapAxis {
  /// A vertical line at an x position.
  vertical,

  /// A horizontal line at a y position.
  horizontal,
}

/// A line a dragged selection snapped to, drawn across the whole slide
/// while the drag lasts.
class SnapGuide {
  /// Creates a guide along [axis] at [position] slide units.
  const SnapGuide(this.axis, this.position);

  /// Which way the line runs.
  final SnapAxis axis;

  /// The x of a vertical guide or the y of a horizontal one, in slide units.
  final double position;

  @override
  bool operator ==(Object other) =>
      other is SnapGuide && other.axis == axis && other.position == position;

  @override
  int get hashCode => Object.hash(axis, position);

  @override
  String toString() => 'SnapGuide(${axis.name}, $position)';
}

/// The outcome of [snapMove]: the move to apply and the guides to draw.
class SnapResult {
  /// Creates a result.
  const SnapResult(this.delta, this.guides);

  /// The move, in slide units, with any snap applied.
  final Offset delta;

  /// The lines the moved box now touches.
  final List<SnapGuide> guides;
}

/// Snaps a box being dragged to the slide and to the other elements.
///
/// [moving] is the dragged selection's bounds before the drag and [delta]
/// the pointer's travel. The box's left edge, center and right edge each try
/// the slide's left edge, center and right edge and those of every element
/// not in [exclude]; the same goes vertically. The closest target within
/// [threshold] slide units on each axis wins, independently, and every
/// target the moved box then lines up with comes back as a guide.
SnapResult snapMove({
  required Rect moving,
  required Offset delta,
  required Slide slide,
  required SlideSize size,
  Set<String> exclude = const {},
  required double threshold,
}) {
  final others = [
    for (final element in slide.elements)
      if (!exclude.contains(element.id)) element.frame.bounds,
  ];
  final xTargets = [
    0.0,
    size.width / 2,
    size.width,
    for (final r in others) ...[r.left, r.center.dx, r.right],
  ];
  final yTargets = [
    0.0,
    size.height / 2,
    size.height,
    for (final r in others) ...[r.top, r.center.dy, r.bottom],
  ];
  final moved = moving.shift(delta);
  final xEdges = [moved.left, moved.center.dx, moved.right];
  final yEdges = [moved.top, moved.center.dy, moved.bottom];
  final dx = _closest(xEdges, xTargets, threshold);
  final dy = _closest(yEdges, yTargets, threshold);
  return SnapResult(delta + Offset(dx ?? 0, dy ?? 0), [
    if (dx != null)
      for (final x in _touched(xEdges, dx, xTargets))
        SnapGuide(SnapAxis.vertical, x),
    if (dy != null)
      for (final y in _touched(yEdges, dy, yTargets))
        SnapGuide(SnapAxis.horizontal, y),
  ]);
}

/// The smallest shift within [threshold] that puts one of [edges] on one of
/// [targets], or `null` when none is that close.
double? _closest(List<double> edges, List<double> targets, double threshold) {
  double? best;
  for (final edge in edges) {
    for (final target in targets) {
      final shift = target - edge;
      if (shift.abs() <= threshold &&
          (best == null || shift.abs() < best.abs())) {
        best = shift;
      }
    }
  }
  return best;
}

/// The distinct [targets] that [edges] shifted by [shift] land on.
Set<double> _touched(List<double> edges, double shift, List<double> targets) =>
    {
      for (final target in targets)
        if (edges.any((edge) => (edge + shift - target).abs() < 0.01)) target,
    };
