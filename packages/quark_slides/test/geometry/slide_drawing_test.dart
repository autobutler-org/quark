import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  group('drawnBox', () {
    test('spans the drag in any direction', () {
      expect(
        drawnBox(const Offset(10, 10), const Offset(50, 30)),
        const Rect.fromLTRB(10, 10, 50, 30),
      );
      expect(
        drawnBox(const Offset(50, 30), const Offset(10, 10)),
        const Rect.fromLTRB(10, 10, 50, 30),
      );
    });

    test('square uses the longer side, toward the pointer', () {
      expect(
        drawnBox(const Offset(100, 100), const Offset(140, 110), square: true),
        const Rect.fromLTRB(100, 100, 140, 140),
      );
      expect(
        drawnBox(const Offset(100, 100), const Offset(90, 40), square: true),
        const Rect.fromLTRB(40, 40, 100, 100),
      );
    });

    test('fromCenter grows out from the point pressed', () {
      expect(
        drawnBox(const Offset(100, 100), const Offset(130, 110),
            fromCenter: true),
        const Rect.fromLTRB(70, 90, 130, 110),
      );
      expect(
        drawnBox(
          const Offset(100, 100),
          const Offset(130, 110),
          fromCenter: true,
          square: true,
        ),
        const Rect.fromLTRB(70, 70, 130, 130),
      );
    });
  });

  group('drawnLine', () {
    test('down-right runs corner to corner, not flipped', () {
      final line = drawnLine(const Offset(10, 10), const Offset(50, 40));
      expect(line.box, const Rect.fromLTRB(10, 10, 50, 40));
      expect(line.flipped, isFalse);
      expect(line.reversed, isFalse);
    });

    test('up-right is flipped; up-left is reversed', () {
      final upRight = drawnLine(const Offset(10, 40), const Offset(50, 10));
      expect(upRight.flipped, isTrue);
      expect(upRight.reversed, isFalse);
      final upLeft = drawnLine(const Offset(50, 40), const Offset(10, 10));
      expect(upLeft.flipped, isFalse);
      expect(upLeft.reversed, isTrue);
      final downLeft = drawnLine(const Offset(50, 10), const Offset(10, 40));
      expect(downLeft.flipped, isTrue);
      expect(downLeft.reversed, isTrue);
    });

    test('a vertical line drawn upward is reversed', () {
      final line = drawnLine(const Offset(10, 50), const Offset(10, 0));
      expect(line.box, const Rect.fromLTRB(10, 0, 10, 50));
      expect(line.flipped, isFalse);
      expect(line.reversed, isTrue);
    });

    test('snap turns to the nearest 45° and keeps the length', () {
      final flat = drawnLine(Offset.zero, const Offset(100, 8), snap: true);
      expect(flat.box.height, 0);
      expect(flat.box.width, closeTo(const Offset(100, 8).distance, 1e-9));
      final diagonal =
          drawnLine(Offset.zero, const Offset(100, 90), snap: true);
      expect(diagonal.box.width, closeTo(diagonal.box.height, 1e-9));
      final vertical =
          drawnLine(Offset.zero, const Offset(-5, -100), snap: true);
      expect(vertical.box.width, 0);
      expect(vertical.reversed, isTrue);
    });

    test('fromCenter makes the point pressed the middle', () {
      final line = drawnLine(
        const Offset(100, 100),
        const Offset(150, 100),
        fromCenter: true,
      );
      expect(line.box, const Rect.fromLTRB(50, 100, 150, 100));
      expect(line.reversed, isFalse);
    });
  });
}
