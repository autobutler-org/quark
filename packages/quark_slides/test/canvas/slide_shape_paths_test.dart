import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  const box = Rect.fromLTRB(10, 20, 210, 120);

  group('shapePath', () {
    test('every kind stays inside its box and reaches each edge', () {
      for (final kind in ShapeKind.values) {
        final bounds = shapePath(kind, box).getBounds();
        expect(bounds.left, closeTo(box.left, 0.5), reason: kind.name);
        expect(bounds.right, closeTo(box.right, 0.5), reason: kind.name);
        expect(bounds.top, closeTo(box.top, 0.5), reason: kind.name);
        expect(bounds.bottom, closeTo(box.bottom, 0.5), reason: kind.name);
      }
    });

    test('a rectangle fills its corners; an ellipse does not', () {
      final corner = box.topLeft + const Offset(1, 1);
      expect(shapePath(ShapeKind.rectangle, box).contains(corner), isTrue);
      expect(shapePath(ShapeKind.ellipse, box).contains(corner), isFalse);
      expect(shapePath(ShapeKind.ellipse, box).contains(box.center), isTrue);
    });

    test('a rounded rectangle rounds by its corner radius', () {
      final nearCorner = box.topLeft + const Offset(3, 3);
      // The default is 15% of the shorter side: 15 units.
      expect(
        shapePath(ShapeKind.roundedRectangle, box).contains(nearCorner),
        isFalse,
      );
      expect(
        shapePath(ShapeKind.roundedRectangle, box, cornerRadius: 0)
            .contains(nearCorner),
        isTrue,
      );
      expect(
        shapePath(ShapeKind.roundedRectangle, box, cornerRadius: 2)
            .contains(nearCorner),
        isTrue,
      );
    });

    test('a corner radius never passes half the shorter side', () {
      // 1000 would turn the box inside out; it is held to 50, a stadium.
      final stadium =
          shapePath(ShapeKind.roundedRectangle, box, cornerRadius: 1000);
      expect(stadium.getBounds(), box);
      expect(stadium.contains(box.center), isTrue);
      expect(stadium.contains(Offset(box.left + 60, box.top + 1)), isTrue);
    });

    test('a triangle points up from its base', () {
      final path = shapePath(ShapeKind.triangle, box);
      expect(path.contains(Offset(box.center.dx, box.top + 2)), isTrue);
      expect(path.contains(box.topLeft + const Offset(2, 2)), isFalse);
      expect(path.contains(box.bottomLeft + const Offset(2, -1)), isTrue);
    });

    test('the arrow points right', () {
      final path = shapePath(ShapeKind.arrow, box);
      expect(path.contains(Offset(box.right - 2, box.center.dy)), isTrue);
      expect(path.contains(Offset(box.left + 2, box.center.dy)), isTrue);
      // The shaft is narrower than the head.
      expect(path.contains(Offset(box.left + 2, box.top + 5)), isFalse);
      expect(path.contains(Offset(box.left + 122, box.top + 5)), isTrue);
    });
  });

  test('starPoints alternates outer points and inner corners from the top', () {
    const square = Rect.fromLTRB(0, 0, 100, 100);
    final points = starPoints(square);
    expect(points, hasLength(10));
    expect(points.first.dx, closeTo(50, 1e-9));
    expect(points.first.dy, closeTo(0, 1e-9));
    // The side points touch the edges and the lower points the bottom.
    expect(points[2].dx, closeTo(100, 1e-9));
    expect(points[8].dx, closeTo(0, 1e-9));
    expect(points[4].dy, closeTo(100, 1e-9));
    expect(points[6].dy, closeTo(100, 1e-9));
    // It is mirror-symmetric about the vertical center line.
    for (var i = 1; i < 10; i++) {
      expect(points[i].dx, closeTo(100 - points[10 - i].dx, 1e-9));
      expect(points[i].dy, closeTo(points[10 - i].dy, 1e-9));
    }
    // Inner corners sit well inside the outer points.
    expect(
      (points[1] - square.center).distance,
      lessThan((points[0] - square.center).distance),
    );
  });

  test('lineEnds runs corner to corner, or across when flipped', () {
    const size = Size(40, 30);
    expect(lineEnds(size), (Offset.zero, const Offset(40, 30)));
    expect(
      lineEnds(size, flipped: true),
      (const Offset(0, 30), const Offset(40, 0)),
    );
  });

  group('arrowheadPath', () {
    test('points at the tip, away from the line', () {
      final head = arrowheadPath(Offset.zero, const Offset(100, 0), 2);
      final bounds = head.getBounds();
      expect(bounds.right, closeTo(100, 1e-9));
      expect(bounds.left, closeTo(100 - arrowheadLength(2), 1e-9));
      expect(bounds.height, closeTo(arrowheadLength(2), 1e-9));
      expect(head.contains(const Offset(95, 0)), isTrue);
    });

    test('grows with the stroke, never below 12', () {
      expect(arrowheadLength(1), 12);
      expect(arrowheadLength(10), 40);
    });

    test('is empty when the line has no length', () {
      expect(
        arrowheadPath(const Offset(5, 5), const Offset(5, 5), 2)
            .computeMetrics()
            .isEmpty,
        isTrue,
      );
    });
  });

  group('dashes', () {
    test('dashIntervals scales with the stroke; solid has none', () {
      expect(dashIntervals(StrokeDash.solid, 4), isNull);
      expect(dashIntervals(StrokeDash.dash, 4), [12, 8]);
      expect(dashIntervals(StrokeDash.dot, 4), [4, 4]);
      expect(dashIntervals(StrokeDash.dashDot, 2), [6, 3, 2, 3]);
      // Hairlines still dash visibly.
      expect(dashIntervals(StrokeDash.dot, 0.1), [1, 1]);
    });

    test('dashedPath keeps the on lengths and drops the gaps', () {
      final line = Path()
        ..moveTo(0, 0)
        ..lineTo(100, 0);
      final dashed = dashedPath(line, [10, 10]);
      final pieces = dashed.computeMetrics().toList();
      expect(pieces, hasLength(5));
      expect(
        pieces.fold<double>(0, (sum, m) => sum + m.length),
        closeTo(50, 1e-3),
      );
    });

    test('dashedPath follows every contour of a closed shape', () {
      final rect = Path()..addRect(const Rect.fromLTRB(0, 0, 10, 10));
      final dashed = dashedPath(rect, [5, 5]);
      expect(
        dashed.computeMetrics().fold<double>(0, (sum, m) => sum + m.length),
        closeTo(20, 1e-3),
      );
    });
  });
}
