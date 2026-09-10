// The transparency backdrop.
//
// There is nothing to tap and no callbacks, so what these assert is that the
// child still renders on both viewports, that the painter is there, and that
// its colors track the theme rather than a hardcoded pair.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/layout/quark_checkerboard/checkerboard_painter.dart';

import '../support/pump.dart';

/// The painter under the checkerboard, whichever [CustomPaint] wraps it.
CheckerboardPainter painterOf(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<CheckerboardPainter>();
  expect(painters, hasLength(1));
  return painters.single;
}

void main() {
  testBothViewports('paints the board behind its child', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkCheckerboard(child: Text('artwork')),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('artwork'), findsOneWidget);
    expect(painterOf(tester).squareSize, QuarkCheckerboard.defaultSquareSize);
  });

  testBothViewports('the child sizes the board', (tester, size) async {
    await pumpAt(
      tester,
      const Center(
        child: QuarkCheckerboard(child: SizedBox(width: 120, height: 90)),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(QuarkCheckerboard)), const Size(120, 90));
  });

  testBothViewports('an explicit square size reaches the painter', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkCheckerboard(squareSize: 4, child: Text('artwork')),
      size: size,
    );

    expect(painterOf(tester).squareSize, 4);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the squares come from the tokens', (tester) async {
      await pumpAt(
        tester,
        const QuarkCheckerboard(child: Text('artwork')),
        brightness: brightness,
      );

      final painter = painterOf(tester);
      expect(painter.light, tokens.card);
      expect(painter.dark, tokens.border);
      expect(
        painter.light,
        isNot(painter.dark),
        reason: 'a checkerboard of one color is not a checkerboard',
      );
    });
  }

  test('repaints only when the board actually changes', () {
    const painter = CheckerboardPainter(
      light: Color(0xFF000000),
      dark: Color(0xFF111111),
      squareSize: 16,
    );

    expect(painter.shouldRepaint(painter), isFalse);
    expect(
      painter.shouldRepaint(
        const CheckerboardPainter(
          light: Color(0xFF222222),
          dark: Color(0xFF111111),
          squareSize: 16,
        ),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        const CheckerboardPainter(
          light: Color(0xFF000000),
          dark: Color(0xFF111111),
          squareSize: 8,
        ),
      ),
      isTrue,
    );
  });
}
