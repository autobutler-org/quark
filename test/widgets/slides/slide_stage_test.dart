import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/slide_stage.dart';
import 'package:quark_slides/quark_slides.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// The read-only stage the editor shows a slide on until the interactive
/// canvas lands (#1161).
void main() {
  final slide = Slide(
    id: 's1',
    background: const SlideBackground(color: SlideColor(0xFF112233)),
    elements: [
      TextBox(
        id: 't1',
        frame: ElementFrame(x: 100, y: 100, width: 1000, height: 200),
        paragraphs: [TextParagraph.plain('Hello slides')],
      ),
      ShapeElement(
        id: 'e1',
        kind: ShapeKind.ellipse,
        frame: ElementFrame(x: 1200, y: 600, width: 400, height: 300),
        fill: const SlideColor(0xFF3366FF),
      ),
      LineElement(
        id: 'l1',
        frame: ElementFrame(x: 0, y: 0, width: 500, height: 500),
        stroke: Stroke(width: 4),
      ),
      ImageElement(
        id: 'i1',
        frame: ElementFrame(x: 0, y: 700, width: 300, height: 300),
        source: 'photo.png',
        altText: 'A photo',
      ),
    ],
  );

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('draws every element at the deck ratio ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SlideStage(
                slide: slide,
                size: SlideSize.widescreen,
                semanticLabel: 'Slide 1 of 1',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Hello slides'), findsOneWidget);
      final box = tester.getSize(find.byType(SlideStage));
      expect(box.width / box.height, closeTo(16 / 9, 0.01));
      expect(box.width, lessThanOrEqualTo(size.width));
      expect(find.bySemanticsLabel('Slide 1 of 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('slide text ignores the device text scale', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SlideStage(slide: slide, size: SlideSize.widescreen),
        ),
      ),
    );
    final text = tester.widget<RichText>(
      find
          .descendant(
            of: find.byType(SlideStage),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(text.textScaler, TextScaler.noScaling);
  });
}
