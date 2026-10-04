/// The geometry of drawing a new element with a drag: the box a shape
/// fills and the segment a line runs along, with the Shift and Alt
/// modifiers applied. `SlideCanvas` calls these on every pointer move; they
/// are plain arithmetic in slide units.
library;

import 'dart:math' as math;
import 'dart:ui';

/// The box a drag from [start] to [end] draws, in slide units.
///
/// [square] keeps the sides equal, as Shift does, using the longer of the
/// two and growing toward the pointer. [fromCenter] makes [start] the
/// center rather than a corner, as Alt does.
///
/// ```dart
/// drawnBox(Offset.zero, const Offset(40, 10), square: true);
/// // Rect.fromLTRB(0, 0, 40, 40)
/// ```
Rect drawnBox(
  Offset start,
  Offset end, {
  bool square = false,
  bool fromCenter = false,
}) {
  var delta = end - start;
  if (square) {
    final side = math.max(delta.dx.abs(), delta.dy.abs());
    delta = Offset(
      delta.dx.isNegative ? -side : side,
      delta.dy.isNegative ? -side : side,
    );
  }
  return fromCenter
      ? Rect.fromPoints(start - delta, start + delta)
      : Rect.fromPoints(start, start + delta);
}

/// A straight segment drawn by a drag, as a line element stores it: the
/// [box] it spans, whether it runs bottom-left to top-right ([flipped]),
/// and whether the drag ran against the box's own direction ([reversed]) —
/// right to left, or upward on a vertical line — so the line's start and
/// end caps belong swapped.
typedef DrawnLine = ({Rect box, bool flipped, bool reversed});

/// The line a drag from [start] to [end] draws, in slide units.
///
/// [snap] turns it to the nearest multiple of 45° about [start], keeping
/// its length, as Shift does. [fromCenter] makes [start] the middle of the
/// line, as Alt does.
///
/// ```dart
/// drawnLine(Offset.zero, const Offset(100, 8), snap: true).box;
/// // Rect.fromLTRB(0, 0, 100.32, 0): the length of the drag, laid flat
/// ```
DrawnLine drawnLine(
  Offset start,
  Offset end, {
  bool snap = false,
  bool fromCenter = false,
}) {
  var delta = end - start;
  if (snap && delta != Offset.zero) {
    const step = math.pi / 4;
    final angle = (delta.direction / step).roundToDouble() * step;
    delta = Offset.fromDirection(angle, delta.distance);
    // Exact zeros, so a horizontal line has a zero-height box.
    delta = Offset(_clean(delta.dx), _clean(delta.dy));
  }
  final from = fromCenter ? start - delta : start;
  final to = start + delta;
  final d = to - from;
  final flipped = d.dx * d.dy < 0;
  final reversed = d.dx < 0 || (d.dx == 0 && d.dy < 0);
  return (box: Rect.fromPoints(from, to), flipped: flipped, reversed: reversed);
}

double _clean(double value) => value.abs() < 1e-9 ? 0 : value;
