import 'dart:math' as math;

import '../model/element_frame.dart';
import '../model/slide_element.dart';

/// An axis-aligned box in slide units: what alignment lines up and what a
/// group's frame is fitted to.
typedef SlideBox = ({double left, double top, double right, double bottom});

/// The smallest axis-aligned [SlideBox] holding [frame] after its rotation.
///
/// Plain Dart, like the rest of this file, so `SlideDocumentController` can
/// use it without Flutter; `FrameGeometry.bounds` is the same box as a
/// `Rect`.
SlideBox frameBox(ElementFrame frame) {
  if (frame.rotation % 360 == 0) {
    return (
      left: frame.x,
      top: frame.y,
      right: frame.x + frame.width,
      bottom: frame.y + frame.height,
    );
  }
  final radians = frame.rotation * math.pi / 180;
  final cos = math.cos(radians).abs();
  final sin = math.sin(radians).abs();
  final halfWidth = (frame.width * cos + frame.height * sin) / 2;
  final halfHeight = (frame.width * sin + frame.height * cos) / 2;
  final cx = frame.x + frame.width / 2;
  final cy = frame.y + frame.height / 2;
  return (
    left: cx - halfWidth,
    top: cy - halfHeight,
    right: cx + halfWidth,
    bottom: cy + halfHeight,
  );
}

/// The box holding every box in [boxes], or `null` when there are none.
SlideBox? unionBox(Iterable<SlideBox> boxes) {
  SlideBox? union;
  for (final b in boxes) {
    union = union == null
        ? b
        : (
            left: math.min(union.left, b.left),
            top: math.min(union.top, b.top),
            right: math.max(union.right, b.right),
            bottom: math.max(union.bottom, b.bottom),
          );
  }
  return union;
}

/// Rotates the vector ([dx], [dy]) by [degrees], clockwise on screen (y
/// grows downward) — the plain-Dart twin of `rotateOffset`.
(double, double) rotateVector(double dx, double dy, double degrees) {
  if (degrees % 360 == 0) return (dx, dy);
  final radians = degrees * math.pi / 180;
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  return (dx * cos - dy * sin, dx * sin + dy * cos);
}

/// [degrees] turned into [0, 360).
double normalizedRotation(double degrees) {
  final turned = degrees % 360;
  return turned == 360 ? 0 : turned;
}

/// The frame, in the space [group] lives in, of a child whose group-local
/// frame is [child]: placed by the group's position and turned by its
/// rotation. [frameInGroup] is its inverse.
ElementFrame frameInParent(ElementFrame group, ElementFrame child) {
  if (group.rotation % 360 == 0) {
    return child.translate(group.x, group.y);
  }
  final (dx, dy) = rotateVector(
    child.x + child.width / 2 - group.width / 2,
    child.y + child.height / 2 - group.height / 2,
    group.rotation,
  );
  return child.copyWith(
    x: group.x + group.width / 2 + dx - child.width / 2,
    y: group.y + group.height / 2 + dy - child.height / 2,
    rotation: normalizedRotation(group.rotation + child.rotation),
  );
}

/// The group-local frame of [frame], given in the space [group] lives in;
/// the inverse of [frameInParent].
ElementFrame frameInGroup(ElementFrame group, ElementFrame frame) {
  if (group.rotation % 360 == 0) {
    return frame.translate(-group.x, -group.y);
  }
  final (dx, dy) = rotateVector(
    frame.x + frame.width / 2 - group.x - group.width / 2,
    frame.y + frame.height / 2 - group.y - group.height / 2,
    -group.rotation,
  );
  return frame.copyWith(
    x: group.width / 2 + dx - frame.width / 2,
    y: group.height / 2 + dy - frame.height / 2,
    rotation: normalizedRotation(frame.rotation - group.rotation),
  );
}

/// A group with id [id] holding [members], which keep their stacking order.
///
/// The group's frame is the box around the members' rotated bounds, with
/// no rotation, and each member's frame becomes group-local, so nothing
/// moves on the slide. [members] are in whatever space the group will live
/// in: the slide, or the group they are taken out of.
GroupElement groupOf(String id, List<SlideElement> members) {
  final box = unionBox(members.map((e) => frameBox(e.frame)));
  if (box == null) throw ArgumentError.value(members, 'members', 'is empty');
  final frame = ElementFrame(
    x: box.left,
    y: box.top,
    width: box.right - box.left,
    height: box.bottom - box.top,
  );
  return GroupElement(
    id: id,
    frame: frame,
    children: [
      for (final e in members) e.withFrame(frameInGroup(frame, e.frame)),
    ],
  );
}

/// [group]'s children with their frames in the space the group lives in —
/// what ungrouping puts in its place. Nothing moves on the slide.
List<SlideElement> ungroupChildren(GroupElement group) => [
      for (final child in group.children)
        child.withFrame(frameInParent(group.frame, child.frame)),
    ];

/// [group] given [frame], its children scaled with it.
///
/// Each child's position and size scale by the ratio of the new width to
/// the old, and of the new height to the old, so the children keep their
/// places within the group; a nested group scales its own children the same
/// way. A child turned by other than a quarter turn is scaled along the
/// group's axes, not its own, so a stretch skews it slightly. Text keeps
/// its size: only frames scale.
GroupElement resizeGroup(GroupElement group, ElementFrame frame) {
  final old = group.frame;
  final sx = old.width == 0 ? 1.0 : frame.width / old.width;
  final sy = old.height == 0 ? 1.0 : frame.height / old.height;
  if (sx == 1 && sy == 1) return group.withFrame(frame);
  return group.copyWith(
    frame: frame,
    children: [
      for (final child in group.children)
        reframe(
          child,
          child.frame.copyWith(
            x: child.frame.x * sx,
            y: child.frame.y * sy,
            width: child.frame.width * sx,
            height: child.frame.height * sy,
          ),
        ),
    ],
  );
}

/// [element] given [frame]; a group whose size changes scales its children
/// with it (see [resizeGroup]).
SlideElement reframe(SlideElement element, ElementFrame frame) =>
    element is GroupElement &&
            (frame.width != element.frame.width ||
                frame.height != element.frame.height)
        ? resizeGroup(element, frame)
        : element.withFrame(frame);

/// [group] with its frame fitted to its children's bounds again, after one
/// of them moved, grew or shrank. Nothing moves on the slide: the frame
/// changes and the children's group-local frames shift to match. A group
/// whose frame already fits comes back as it is.
GroupElement fitGroup(GroupElement group) {
  final box = unionBox(group.children.map((e) => frameBox(e.frame)));
  final frame = group.frame;
  const epsilon = 1e-9;
  if (box == null ||
      (box.left.abs() < epsilon &&
          box.top.abs() < epsilon &&
          (box.right - frame.width).abs() < epsilon &&
          (box.bottom - frame.height).abs() < epsilon)) {
    return group;
  }
  final placed = frameInParent(
    frame,
    ElementFrame(
      x: box.left,
      y: box.top,
      width: box.right - box.left,
      height: box.bottom - box.top,
    ),
  );
  return group.copyWith(
    frame: frame.copyWith(
      x: placed.x,
      y: placed.y,
      width: placed.width,
      height: placed.height,
    ),
    children: [
      for (final c in group.children)
        c.withFrame(c.frame.translate(-box.left, -box.top)),
    ],
  );
}
