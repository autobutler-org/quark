import 'dart:math' as math;
import 'dart:ui';

import '../model/element_frame.dart';
import '../model/slide.dart';
import '../model/slide_element.dart';
import 'slide_handle.dart';

/// Rotates [point] about the origin by [degrees], clockwise on screen (y
/// grows downward).
Offset rotateOffset(Offset point, double degrees) {
  if (degrees == 0) return point;
  final radians = degrees * math.pi / 180;
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  return Offset(
    point.dx * cos - point.dy * sin,
    point.dx * sin + point.dy * cos,
  );
}

/// Geometry of an [ElementFrame] in slide units: its rotated corners and
/// bounds, where its handles sit, and the frames dragging them produces.
///
/// Every gesture on the canvas is worked out here, away from widgets, so it
/// can be tested as plain arithmetic.
extension FrameGeometry on ElementFrame {
  /// The box before rotation.
  Rect get rect => Rect.fromLTRB(x, y, x + width, y + height);

  /// The center, which rotation leaves in place.
  Offset get center => Offset(x + width / 2, y + height / 2);

  /// Converts [local], relative to [center] along the frame's own axes
  /// before rotation, to a slide point.
  Offset toSlide(Offset local) => center + rotateOffset(local, rotation);

  /// Converts the slide point [point] to the frame's own axes before rotation,
  /// relative to [center].
  Offset toLocal(Offset point) => rotateOffset(point - center, -rotation);

  /// The four corners after rotation, clockwise from the top-left.
  List<Offset> get corners {
    final w = width / 2;
    final h = height / 2;
    return [
      toSlide(Offset(-w, -h)),
      toSlide(Offset(w, -h)),
      toSlide(Offset(w, h)),
      toSlide(Offset(-w, h)),
    ];
  }

  /// The smallest axis-aligned box holding the rotated frame.
  Rect get bounds {
    if (rotation % 360 == 0) return rect;
    final points = corners;
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final p in points.skip(1)) {
      left = math.min(left, p.dx);
      right = math.max(right, p.dx);
      top = math.min(top, p.dy);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Whether [point] is inside the rotated frame, grown by [tolerance] on
  /// every side.
  bool contains(Offset point, {double tolerance = 0}) {
    final local = toLocal(point);
    return local.dx.abs() <= width / 2 + tolerance &&
        local.dy.abs() <= height / 2 + tolerance;
  }

  /// Where [handle] sits, in slide units. The rotate handle sits
  /// [rotateOffset] slide units above the middle of the top edge.
  Offset handlePoint(SlideHandle handle, {double rotateOffset = 0}) {
    final local = Offset(handle.dx * width / 2, handle.dy * height / 2);
    return toSlide(
      handle == SlideHandle.rotate ? local - Offset(0, rotateOffset) : local,
    );
  }

  /// The frame after dragging the resize [handle] by [delta] slide units.
  ///
  /// The edges the handle sits on follow the pointer along the frame's own
  /// axes, and the opposite edges (or, for an edge handle, the center line
  /// across it) stay where they are on the slide, so a rotated frame grows
  /// the way it looks. No edge passes its opposite: a resized dimension is
  /// at least [minExtent]. [keepAspect] keeps the width-to-height ratio, the
  /// way Shift does at a corner and an image always does: at an edge handle
  /// the other side scales to match, about the center line across it.
  ElementFrame resized(
    SlideHandle handle,
    Offset delta, {
    bool keepAspect = false,
    double minExtent = 1,
  }) {
    assert(handle.isResize, 'the rotate handle does not resize');
    final local = rotateOffset(delta, -rotation);
    var newWidth = handle.dx == 0
        ? width
        : math.max(minExtent, width + handle.dx * local.dx);
    var newHeight = handle.dy == 0
        ? height
        : math.max(minExtent, height + handle.dy * local.dy);
    if (keepAspect && width > 0 && height > 0) {
      // A corner follows whichever side grew more; an edge scales the
      // other side to match, about the center line across it.
      final scale = handle.isCorner
          ? math.max(newWidth / width, newHeight / height)
          : (handle.dx == 0 ? newHeight / height : newWidth / width);
      newWidth = math.max(minExtent, width * scale);
      newHeight = math.max(minExtent, height * scale);
    }
    if (rotation % 360 == 0) {
      // With no rotation, the fixed edges keep their exact coordinates.
      double fixed(int dir, double start, double old, double next) => dir < 0
          ? start + old - next
          : (dir == 0 ? start + (old - next) / 2 : start);
      return copyWith(
        x: fixed(handle.dx, x, width, newWidth),
        y: fixed(handle.dy, y, height, newHeight),
        width: newWidth,
        height: newHeight,
      );
    }
    final anchor = toSlide(
      Offset(-handle.dx * width / 2, -handle.dy * height / 2),
    );
    final newCenter = anchor -
        rotateOffset(
          Offset(-handle.dx * newWidth / 2, -handle.dy * newHeight / 2),
          rotation,
        );
    return copyWith(
      x: newCenter.dx - newWidth / 2,
      y: newCenter.dy - newHeight / 2,
      width: newWidth,
      height: newHeight,
    );
  }

  /// The rotation, in degrees within [0, 360), that turns the frame's top
  /// toward [point], as dragging the rotate handle there does. [snap] rounds
  /// it to a multiple of [snapStep], as Shift does.
  double rotationToward(Offset point,
      {bool snap = false, double snapStep = 15}) {
    final toPoint = point - center;
    var degrees = math.atan2(toPoint.dy, toPoint.dx) * 180 / math.pi + 90;
    if (snap) degrees = (degrees / snapStep).roundToDouble() * snapStep;
    degrees %= 360;
    return degrees == 360 ? 0 : degrees;
  }
}

/// Hit testing a [SlideElement] by its shape.
extension ElementHitTest on SlideElement {
  /// Whether [point], in slide units, lands on the element.
  ///
  /// Most elements are hit anywhere inside their rotated frame. A line is
  /// hit within half its stroke width, or [tolerance], of the segment it
  /// draws, since its frame can be zero-thin and a thin diagonal line covers
  /// little of its frame.
  bool hitTest(Offset point, {double tolerance = 0}) {
    final element = this;
    if (element is! LineElement) return frame.contains(point);
    final w = frame.width / 2;
    final h = frame.height / 2;
    final start = element.flipped ? Offset(-w, h) : Offset(-w, -h);
    final end = -start;
    final reach = math.max(tolerance, element.stroke.width / 2);
    return _distanceToSegment(frame.toLocal(point), start, end) <= reach;
  }
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Finding elements on a [Slide] by position.
extension SlideHitTest on Slide {
  /// The front element under [point], or `null` over empty slide.
  /// [tolerance] is passed to [ElementHitTest.hitTest].
  SlideElement? elementAt(Offset point, {double tolerance = 0}) {
    for (final element in elements.reversed) {
      if (element.hitTest(point, tolerance: tolerance)) return element;
    }
    return null;
  }

  /// The ids, back to front, of every element whose rotated bounds lie
  /// wholly inside [area] — what a marquee drag selects.
  List<String> elementsInside(Rect area) => [
        for (final element in elements)
          if (_encloses(area, element.frame.bounds)) element.id,
      ];

  /// The smallest box holding the bounds of every element in [ids], or
  /// `null` when none of them is on the slide.
  Rect? boundsOf(Iterable<String> ids) {
    final wanted = ids.toSet();
    Rect? union;
    for (final element in elements) {
      if (!wanted.contains(element.id)) continue;
      final bounds = element.frame.bounds;
      union = union?.expandToInclude(bounds) ?? bounds;
    }
    return union;
  }
}

bool _encloses(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;
