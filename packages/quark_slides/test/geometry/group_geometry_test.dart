import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

ShapeElement shape(String id, ElementFrame frame) =>
    ShapeElement(id: id, frame: frame);

ElementFrame f(double x, double y, double w, double h, [double r = 0]) =>
    ElementFrame(x: x, y: y, width: w, height: h, rotation: r);

/// Matches a frame within a small tolerance, for rotated arithmetic.
Matcher frameNear(ElementFrame expected) => isA<ElementFrame>()
    .having((e) => e.x, 'x', closeTo(expected.x, 1e-6))
    .having((e) => e.y, 'y', closeTo(expected.y, 1e-6))
    .having((e) => e.width, 'width', closeTo(expected.width, 1e-6))
    .having((e) => e.height, 'height', closeTo(expected.height, 1e-6))
    .having((e) => e.rotation % 360, 'rotation',
        closeTo(expected.rotation % 360, 1e-6));

void main() {
  group('frameBox', () {
    test('an unrotated frame is its own box', () {
      expect(frameBox(f(10, 20, 30, 40)),
          (left: 10.0, top: 20.0, right: 40.0, bottom: 60.0));
    });

    test('a quarter turn swaps width and height about the center', () {
      final box = frameBox(f(0, 0, 100, 20, 90));
      expect(box.left, closeTo(40, 1e-9));
      expect(box.top, closeTo(-40, 1e-9));
      expect(box.right, closeTo(60, 1e-9));
      expect(box.bottom, closeTo(60, 1e-9));
    });

    test('matches FrameGeometry.bounds', () {
      final frame = f(100, 50, 300, 120, 33);
      final box = frameBox(frame);
      final rect = frame.bounds;
      expect(box.left, closeTo(rect.left, 1e-9));
      expect(box.bottom, closeTo(rect.bottom, 1e-9));
    });
  });

  group('frameInParent and frameInGroup', () {
    test('an unrotated group only offsets', () {
      expect(frameInParent(f(100, 200, 500, 500), f(10, 20, 30, 40)),
          f(110, 220, 30, 40));
      expect(frameInGroup(f(100, 200, 500, 500), f(110, 220, 30, 40)),
          f(10, 20, 30, 40));
    });

    test('a rotated group turns its child about the group center', () {
      // A 100×100 group turned a quarter: the child in its top-left corner
      // ends up in the top-right, turned with it.
      final placed = frameInParent(f(0, 0, 100, 100, 90), f(0, 0, 20, 20));
      expect(placed, frameNear(f(80, 0, 20, 20, 90)));
    });

    test('are inverses, rotation included', () {
      final group = f(140, 60, 400, 250, 37);
      final child = f(30, 50, 120, 80, 12);
      expect(
          frameInGroup(group, frameInParent(group, child)), frameNear(child));
    });
  });

  group('groupOf and ungroupChildren', () {
    final a = shape('a', f(100, 100, 200, 100));
    final b = shape('b', f(400, 300, 100, 100, 45));

    test('the group frames its members’ rotated bounds, unrotated', () {
      final group = groupOf('g', [a, b]);
      final bBox = frameBox(b.frame);
      expect(group.frame,
          frameNear(f(100, 100, bBox.right - 100, bBox.bottom - 100)));
      expect(group.children.map((e) => e.id), ['a', 'b']);
      expect(group.children.first.frame, f(0, 0, 200, 100));
    });

    test('ungrouping puts every member back where it was', () {
      final freed = ungroupChildren(groupOf('g', [a, b]));
      expect(freed.first, a);
      expect(freed.last.frame, frameNear(b.frame));
    });

    test('ungrouping a rotated group keeps the children where they show', () {
      final group = groupOf('g', [a, b]);
      final turned = group.withFrame(group.frame.copyWith(rotation: 90));
      final child = ungroupChildren(turned).first;
      expect(
        child.frame,
        frameNear(frameInParent(turned.frame, turned.children.first.frame)),
      );
      expect(child.frame.rotation, closeTo(90, 1e-9));
    });

    test('an empty group is refused', () {
      expect(() => groupOf('g', const []), throwsArgumentError);
    });
  });

  group('resizeGroup', () {
    test('scales the children’s places and sizes with the frame', () {
      final group = groupOf('g', [
        shape('a', f(0, 0, 100, 100)),
        shape('b', f(100, 100, 100, 100)),
      ]);
      final bigger = resizeGroup(group, f(0, 0, 400, 100));
      expect(bigger.children[0].frame, f(0, 0, 200, 50));
      expect(bigger.children[1].frame, f(200, 50, 200, 50));
    });

    test('scales a nested group’s children too', () {
      final inner = groupOf('in', [
        shape('a', f(0, 0, 50, 50)),
        shape('b', f(50, 50, 50, 50)),
      ]);
      final outer = groupOf('out', [inner, shape('c', f(100, 0, 100, 100))]);
      final doubled = resizeGroup(outer, f(0, 0, 400, 200));
      final nested = doubled.children.first as GroupElement;
      expect(nested.frame, f(0, 0, 200, 200));
      expect(nested.children.last.frame, f(100, 100, 100, 100));
    });

    test('reframe moves a group without touching its children', () {
      final group = groupOf('g', [shape('a', f(0, 0, 10, 10))]);
      final moved = reframe(group, f(50, 50, 10, 10)) as GroupElement;
      expect(moved.children, group.children);
    });
  });

  group('fitGroup', () {
    test('a fitted group comes back unchanged', () {
      final group = groupOf('g', [
        shape('a', f(0, 0, 10, 10)),
        shape('b', f(20, 20, 10, 10)),
      ]);
      expect(identical(fitGroup(group), group), isTrue);
    });

    test('refits after a child moves, keeping every child in place', () {
      final group = groupOf('g', [
        shape('a', f(100, 100, 100, 100)),
        shape('b', f(300, 300, 100, 100)),
      ]).withFrame(f(100, 100, 300, 300, 30));
      final before = [
        for (final c in group.children) frameInParent(group.frame, c.frame),
      ];
      final stretched = group.copyWith(children: [
        group.children.first.withFrame(f(-50, -20, 100, 100)),
        group.children.last,
      ]);
      final fitted = fitGroup(stretched);
      expect(fitted.frame.width, closeTo(350, 1e-9));
      expect(fitted.frame.height, closeTo(320, 1e-9));
      expect(fitted.frame.rotation, 30);
      expect(fitted.children.first.frame, frameNear(f(0, 0, 100, 100)));
      // The untouched child shows where it did.
      expect(
        frameInParent(fitted.frame, fitted.children.last.frame),
        frameNear(before.last),
      );
    });
  });

  group('SlideTree', () {
    final slide = Slide(id: 's', elements: [
      shape('top', f(0, 0, 10, 10)),
      GroupElement(id: 'g', frame: f(100, 100, 200, 200, 90), children: [
        shape('a', f(0, 0, 50, 50)),
        GroupElement(id: 'inner', frame: f(100, 100, 100, 100), children: [
          shape('deep', f(0, 0, 100, 100)),
        ]),
      ]),
    ]);

    test('walks every element depth first', () {
      expect(slide.allElements.map((e) => e.id),
          ['top', 'g', 'a', 'inner', 'deep']);
    });

    test('finds and places nested elements', () {
      expect(slide.findElement('deep'), isA<ShapeElement>());
      expect(slide.findElement('nope'), isNull);
      expect(slide.ancestorsOf('deep')!.map((g) => g.id), ['g', 'inner']);
      expect(slide.ancestorsOf('top'), isEmpty);
      expect(slide.ancestorsOf('nope'), isNull);
      expect(slide.parentOf('a')!.id, 'g');
      expect(slide.parentOf('top'), isNull);
      // The group's top-left quarter turns to its top-right.
      expect(slide.frameOnSlide('a'), frameNear(f(250, 100, 50, 50, 90)));
      expect(slide.frameOnSlide('deep'), frameNear(f(100, 200, 100, 100, 90)));
    });

    test('hit tests a group by its children, not its gaps', () {
      final gappy = GroupElement(id: 'g', frame: f(0, 0, 300, 100), children: [
        shape('l', f(0, 0, 100, 100)),
        shape('r', f(200, 0, 100, 100)),
      ]);
      expect(gappy.hitTest(const Offset(50, 50)), isTrue);
      expect(gappy.hitTest(const Offset(150, 50)), isFalse);
      expect(gappy.hitTest(const Offset(250, 50)), isTrue);
    });
  });
}
