import '../model/element_frame.dart';
import 'group_geometry.dart';

/// Which edge or center line [alignFrames] lines elements up on.
enum ElementAlignment {
  /// Left edges.
  left,

  /// Vertical center lines.
  center,

  /// Right edges.
  right,

  /// Top edges.
  top,

  /// Horizontal center lines.
  middle,

  /// Bottom edges.
  bottom,
}

/// Which way [distributeFrames] spaces elements out.
enum DistributeAxis {
  /// Equal gaps left to right.
  horizontal,

  /// Equal gaps top to bottom.
  vertical,
}

/// Which sides [matchFrameSizes] makes equal.
enum SizeMatch {
  /// The width.
  width,

  /// The height.
  height,

  /// Both.
  both,
}

/// [frames] moved so that their [alignment] edges or center lines meet.
///
/// Elements line up by their bounds after rotation — what the eye sees —
/// and only move: a rotated element keeps its size and rotation. They line
/// up on the box around all of them, or on [within] when given (the slide,
/// for "align to slide"). Keys are element ids; every frame comes back,
/// moved or not.
///
/// ```dart
/// alignFrames({'a': a, 'b': b}, ElementAlignment.left);
/// alignFrames({'a': a}, ElementAlignment.center, within: slideBox);
/// ```
Map<String, ElementFrame> alignFrames(
  Map<String, ElementFrame> frames,
  ElementAlignment alignment, {
  SlideBox? within,
}) {
  final target = within ?? unionBox(frames.values.map(frameBox));
  if (target == null) return const {};
  return {
    for (final MapEntry(:key, value: frame) in frames.entries)
      key: _alignOne(frame, frameBox(frame), target, alignment),
  };
}

ElementFrame _alignOne(
  ElementFrame frame,
  SlideBox box,
  SlideBox target,
  ElementAlignment alignment,
) {
  double mid(double a, double b) => (a + b) / 2;
  return switch (alignment) {
    ElementAlignment.left => frame.translate(target.left - box.left, 0),
    ElementAlignment.right => frame.translate(target.right - box.right, 0),
    ElementAlignment.center => frame.translate(
        mid(target.left, target.right) - mid(box.left, box.right),
        0,
      ),
    ElementAlignment.top => frame.translate(0, target.top - box.top),
    ElementAlignment.bottom => frame.translate(0, target.bottom - box.bottom),
    ElementAlignment.middle => frame.translate(
        0,
        mid(target.top, target.bottom) - mid(box.top, box.bottom),
      ),
  };
}

/// [frames] spaced out along [axis] with equal gaps between their bounds.
///
/// Without [within], the first and last elements (by their left or top
/// edge) stay put and those between them move, which takes at least three;
/// fewer come back unchanged. With [within] (the slide) the first element
/// moves to its start and the last to its end, which takes at least two.
/// Elements only move. Keys are element ids; every frame comes back.
Map<String, ElementFrame> distributeFrames(
  Map<String, ElementFrame> frames,
  DistributeAxis axis, {
  SlideBox? within,
}) {
  if (frames.length < (within == null ? 3 : 2)) return {...frames};
  final horizontal = axis == DistributeAxis.horizontal;
  double start(SlideBox b) => horizontal ? b.left : b.top;
  double end(SlideBox b) => horizontal ? b.right : b.bottom;
  final boxes = {for (final e in frames.entries) e.key: frameBox(e.value)};
  final order = frames.keys.toList()
    ..sort((a, b) => start(boxes[a]!).compareTo(start(boxes[b]!)));
  final span = within ?? unionBox(boxes.values)!;
  final total = order.fold(0.0, (sum, id) {
    final box = boxes[id]!;
    return sum + end(box) - start(box);
  });
  final gap = (end(span) - start(span) - total) / (order.length - 1);
  var at = start(span);
  final result = <String, ElementFrame>{};
  for (final id in order) {
    final box = boxes[id]!;
    final shift = at - start(box);
    result[id] = horizontal
        ? frames[id]!.translate(shift, 0)
        : frames[id]!.translate(0, shift);
    at += end(box) - start(box) + gap;
  }
  return {for (final id in frames.keys) id: result[id]!};
}

/// [frames] resized to [reference]'s width, height or both, as [match]
/// says, each keeping its top-left corner.
///
/// [reference] is an id among [frames]; left out, it is the frame with the
/// largest area. Keys are element ids; every frame comes back.
Map<String, ElementFrame> matchFrameSizes(
  Map<String, ElementFrame> frames,
  SizeMatch match, {
  String? reference,
}) {
  if (frames.isEmpty) return const {};
  final model = reference == null
      ? frames.values.reduce(
          (a, b) => b.width * b.height > a.width * a.height ? b : a,
        )
      : frames[reference] ??
          (throw ArgumentError.value(reference, 'reference', 'not in frames'));
  final width = match == SizeMatch.height ? null : model.width;
  final height = match == SizeMatch.width ? null : model.height;
  return {
    for (final MapEntry(:key, value: frame) in frames.entries)
      key: frame.copyWith(
        width: width ?? frame.width,
        height: height ?? frame.height,
      ),
  };
}
