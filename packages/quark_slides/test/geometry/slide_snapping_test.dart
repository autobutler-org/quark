import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  final size = SlideSize.widescreen;
  final slide = Slide(id: 's', elements: [
    ShapeElement(
      id: 'other',
      frame: ElementFrame(x: 1500, y: 700, width: 200, height: 100),
    ),
    ShapeElement(
      id: 'moving',
      frame: ElementFrame(x: 100, y: 100, width: 200, height: 100),
    ),
  ]);
  const moving = Rect.fromLTRB(100, 100, 300, 200);

  SnapResult snap(Offset delta) => snapMove(
        moving: moving,
        delta: delta,
        slide: slide,
        size: size,
        exclude: {'moving'},
        threshold: 10,
      );

  test('a box near the slide center snaps onto it with two guides', () {
    // Center would land at (956, 537): 4 and 3 units off (960, 540).
    final result = snap(const Offset(756, 387));
    expect(result.delta, const Offset(760, 390));
    expect(result.guides, [
      const SnapGuide(SnapAxis.vertical, 960),
      const SnapGuide(SnapAxis.horizontal, 540),
    ]);
  });

  test('a box near the left edge snaps to it', () {
    final result = snap(const Offset(-94, 300));
    expect(result.delta, const Offset(-100, 300));
    expect(result.guides, [const SnapGuide(SnapAxis.vertical, 0)]);
  });

  test('a box snaps to another element and names every shared line', () {
    // Left edge lands 3 units short of the other's left edge, and the box
    // is as wide as the other, so the right edges and centers line up too.
    final result = snap(const Offset(1397, 0));
    expect(result.delta, const Offset(1400, 0));
    expect(result.guides.toSet(), {
      const SnapGuide(SnapAxis.vertical, 1500),
      const SnapGuide(SnapAxis.vertical, 1600),
      const SnapGuide(SnapAxis.vertical, 1700),
    });
  });

  test('nothing within the threshold leaves the move alone', () {
    final result = snap(const Offset(333, 222));
    expect(result.delta, const Offset(333, 222));
    expect(result.guides, isEmpty);
  });

  test('the dragged elements are not their own targets', () {
    final result = snapMove(
      moving: moving,
      delta: const Offset(3, 0),
      slide: slide,
      size: size,
      threshold: 10,
    );
    expect(result.delta, Offset.zero);
    final excluded = snap(const Offset(3, 0));
    expect(excluded.delta, const Offset(3, 0));
  });
}
