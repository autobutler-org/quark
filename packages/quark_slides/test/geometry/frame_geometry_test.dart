import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

Matcher offsetNear(Offset expected) => isA<Offset>()
    .having((o) => o.dx, 'dx', closeTo(expected.dx, 1e-6))
    .having((o) => o.dy, 'dy', closeTo(expected.dy, 1e-6));

Matcher frameNear(ElementFrame expected) => isA<ElementFrame>()
    .having((f) => f.x, 'x', closeTo(expected.x, 1e-6))
    .having((f) => f.y, 'y', closeTo(expected.y, 1e-6))
    .having((f) => f.width, 'width', closeTo(expected.width, 1e-6))
    .having((f) => f.height, 'height', closeTo(expected.height, 1e-6))
    .having((f) => f.rotation, 'rotation', expected.rotation);

void main() {
  final square = ElementFrame(x: 100, y: 100, width: 200, height: 100);

  group('frame', () {
    test('a frame at no rotation has its own rect as bounds', () {
      expect(square.center, const Offset(200, 150));
      expect(square.bounds, const Rect.fromLTRB(100, 100, 300, 200));
    });

    test('a quarter turn swaps the bounds about the center', () {
      final turned = square.copyWith(rotation: 90);
      final bounds = turned.bounds;
      expect(bounds.left, closeTo(150, 1e-6));
      expect(bounds.top, closeTo(50, 1e-6));
      expect(bounds.width, closeTo(100, 1e-6));
      expect(bounds.height, closeTo(200, 1e-6));
    });

    test('contains follows the rotation', () {
      final turned = square.copyWith(rotation: 90);
      expect(square.contains(const Offset(110, 140)), isTrue);
      expect(turned.contains(const Offset(110, 140)), isFalse);
      expect(turned.contains(const Offset(190, 60)), isTrue);
    });

    test('handles sit on the rotated edges', () {
      expect(
        square.handlePoint(SlideHandle.bottomRight),
        const Offset(300, 200),
      );
      expect(
        square.handlePoint(SlideHandle.rotate, rotateOffset: 30),
        const Offset(200, 70),
      );
      final turned = square.copyWith(rotation: 90);
      expect(
        turned.handlePoint(SlideHandle.right),
        offsetNear(const Offset(200, 250)),
      );
    });
  });

  group('resize', () {
    test('the bottom-right handle grows the frame from its top-left', () {
      expect(
        square.resized(SlideHandle.bottomRight, const Offset(50, 20)),
        frameNear(ElementFrame(x: 100, y: 100, width: 250, height: 120)),
      );
    });

    test('the left handle keeps the right edge still', () {
      expect(
        square.resized(SlideHandle.left, const Offset(-40, 99)),
        frameNear(ElementFrame(x: 60, y: 100, width: 240, height: 100)),
      );
    });

    test('an edge cannot pass its opposite', () {
      final squashed = square.resized(SlideHandle.top, const Offset(0, 500));
      expect(squashed.height, 1);
      expect(squashed.y, 199);
      final line = ElementFrame(x: 0, y: 0, width: 100, height: 0);
      expect(
        line.resized(SlideHandle.right, const Offset(-500, 0), minExtent: 0),
        frameNear(ElementFrame(x: 0, y: 0, width: 0, height: 0)),
      );
    });

    test('keepAspect scales a corner drag evenly', () {
      expect(
        square.resized(
          SlideHandle.bottomRight,
          const Offset(200, 0),
          keepAspect: true,
        ),
        frameNear(ElementFrame(x: 100, y: 100, width: 400, height: 200)),
      );
    });

    test('a rotated frame resizes along its own axes, anchored opposite', () {
      final turned = square.copyWith(rotation: 90);
      final anchor = turned.handlePoint(SlideHandle.left);
      // The right edge of a quarter-turned frame faces down the slide.
      final grown = turned.resized(SlideHandle.right, const Offset(0, 60));
      expect(grown.width, closeTo(260, 1e-6));
      expect(grown.height, closeTo(100, 1e-6));
      expect(grown.handlePoint(SlideHandle.left), offsetNear(anchor));
    });
  });

  group('rotate', () {
    test('rotationToward points the top at the pointer', () {
      final c = square.center;
      expect(square.rotationToward(c + const Offset(0, -50)), 0);
      expect(square.rotationToward(c + const Offset(50, 0)), 90);
      expect(square.rotationToward(c + const Offset(0, 50)), 180);
      expect(square.rotationToward(c + const Offset(-50, 0)), 270);
    });

    test('snap rounds to 15 degrees', () {
      final c = square.center;
      expect(square.rotationToward(c + const Offset(50, -48), snap: true), 45);
      expect(square.rotationToward(c + const Offset(-1, -50), snap: true), 0);
    });
  });

  group('hit testing', () {
    final slide = Slide(id: 's', elements: [
      ShapeElement(
          id: 'back', frame: ElementFrame(x: 0, y: 0, width: 400, height: 400)),
      ShapeElement(
          id: 'front',
          frame: ElementFrame(x: 100, y: 100, width: 100, height: 100)),
      LineElement(
          id: 'line',
          frame: ElementFrame(x: 500, y: 100, width: 200, height: 0)),
    ]);

    test('elementAt finds the element in front', () {
      expect(slide.elementAt(const Offset(150, 150))?.id, 'front');
      expect(slide.elementAt(const Offset(50, 50))?.id, 'back');
      expect(slide.elementAt(const Offset(900, 900)), isNull);
    });

    test('a flat line is hit within the tolerance', () {
      expect(slide.elementAt(const Offset(600, 104))?.id, isNull);
      expect(
        slide.elementAt(const Offset(600, 104), tolerance: 6)?.id,
        'line',
      );
    });

    test('a diagonal line is hit on its stroke, not across its frame', () {
      final line = LineElement(
        id: 'd',
        frame: ElementFrame(x: 0, y: 0, width: 100, height: 100),
        flipped: true,
      );
      expect(line.hitTest(const Offset(50, 50)), isTrue);
      expect(line.hitTest(const Offset(10, 10)), isFalse);
      expect(line.hitTest(const Offset(10, 90)), isTrue);
    });

    test('elementsInside takes only what the area wholly holds', () {
      expect(
        slide.elementsInside(const Rect.fromLTRB(90, 90, 790, 95)),
        isEmpty,
      );
      expect(
        slide.elementsInside(const Rect.fromLTRB(90, 90, 790, 210)),
        ['front', 'line'],
      );
    });

    test('boundsOf unions the selection', () {
      expect(
        slide.boundsOf(['front', 'line']),
        const Rect.fromLTRB(100, 100, 700, 200),
      );
      expect(slide.boundsOf(['missing']), isNull);
    });
  });
}
