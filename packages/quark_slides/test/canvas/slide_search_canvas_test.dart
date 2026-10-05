import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_slides/src/canvas/slide_text_highlight_painter.dart';

import '../support/canvas_harness.dart';

/// [canvasDeck] with a group `g` holding a box `inner` (`a review`) right
/// of center, notes that say `review`, and a second slide `t` that does too.
Presentation searchDeck() {
  final deck = canvasDeck();
  final slide = deck.slides.single;
  return deck.copyWith(
    slides: [
      slide.copyWith(
        notes: 'review the notes',
        elements: [
          ...slide.elements,
          GroupElement(
            id: 'g',
            frame: ElementFrame(x: 1100, y: 600, width: 400, height: 200),
            children: [
              TextBox(
                id: 'inner',
                frame: ElementFrame(x: 0, y: 0, width: 400, height: 200),
                paragraphs: [TextParagraph.plain('a review')],
              ),
            ],
          ),
        ],
      ),
      Slide(
        id: 't',
        elements: [
          TextBox(
            id: 'other',
            frame: ElementFrame(x: 0, y: 0, width: 400, height: 100),
            paragraphs: [TextParagraph.plain('review')],
          ),
        ],
      ),
    ],
  );
}

List<SlideMatch> search(Presentation deck, String text) => SlideSearch.find(
      deck,
      SlideSearchQuery(text),
      scope: const SlideSearchScope(includeNotes: true),
    ).matches;

/// The highlight painters on screen.
List<SlideTextHighlightPainter> painters(WidgetTester tester) => [
      for (final paint in tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      ))
        if (paint.painter case final SlideTextHighlightPainter p) p,
    ];

void main() {
  testBothViewports('highlights paint behind matches on this slide only', (
    tester,
    size,
  ) async {
    final deck = searchDeck();
    final matches = search(deck, 'review');
    expect(matches.length, 4, reason: 'title, group, notes, other slide');
    await pumpCanvas(
      tester,
      SlideDocumentNotifier(deck),
      size: size,
      highlights: matches,
      currentHighlight: matches.first,
    );
    final drawn = painters(tester);
    expect(drawn.map((p) => p.highlights), [
      [(paragraph: 0, start: 10, end: 16, current: true)],
      [(paragraph: 0, start: 2, end: 8, current: false)],
    ]);
    final title = find.descendant(
      of: elementKey('title'),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SlideTextHighlightPainter,
      ),
    );
    final style = SlideCanvasStyle.fromTheme(ThemeData());
    expect(
      title,
      paints
        ..rect(color: style.currentHighlightColor)
        ..rect(color: style.currentHighlightColor, style: PaintingStyle.stroke),
    );
    expect(
      find.descendant(
        of: elementKey('inner'),
        matching: find.byType(CustomPaint),
      ),
      paints..rect(color: style.highlightColor),
    );
  });

  testWidgets('a highlight sits on the text as it is laid out', (
    tester,
  ) async {
    // The whole centered line highlighted: its box is centered in the
    // 1600-wide title, which it is only when laid out at the box's width.
    final deck = canvasDeck();
    final whole = search(deck, 'Quarterly review').single;
    await pumpCanvas(
      tester,
      SlideDocumentNotifier(deck),
      highlights: [whole],
    );
    final painter = painters(tester).single;
    final text = TextPainter(
      text: painter.span,
      textAlign: painter.textAlign,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 1600, maxWidth: 1600);
    // One box per run: `Quarterly ` and the bold `review`.
    final boxes = text.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 16),
    );
    text.dispose();
    expect(boxes, hasLength(2));
    expect(
      boxes.first.left + boxes.last.right,
      moreOrLessEquals(1600, epsilon: 1),
    );
    expect(boxes.first.left, greaterThan(100));
    expect(
      find.descendant(
        of: elementKey('title'),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is SlideTextHighlightPainter,
        ),
      ),
      paints
        ..rect(rect: boxes.first.toRect())
        ..rect(rect: boxes.last.toRect()),
    );
  });

  testWidgets('no highlights draws no painter', (tester) async {
    await pumpCanvas(tester, SlideDocumentNotifier(searchDeck()));
    expect(painters(tester), isEmpty);
  });

  testWidgets('the current match is revealed: entered, selected, centered', (
    tester,
  ) async {
    final deck = searchDeck();
    final document = SlideDocumentNotifier(deck);
    final matches = search(deck, 'review');
    await pumpCanvas(tester, document, zoom: 2, highlights: matches);
    expect(harness(tester).selection, isEmpty);

    await pumpCanvas(
      tester,
      document,
      zoom: 2,
      highlights: matches,
      currentHighlight: matches[1],
    );
    await tester.pump();
    expect(harness(tester).selection, {'inner'});
    final canvas = tester.getRect(find.byType(SlideCanvas));
    final inner = tester.getRect(elementKey('inner'));
    expect(inner.center.dx, moreOrLessEquals(canvas.center.dx, epsilon: 1));
    expect(inner.center.dy, moreOrLessEquals(canvas.center.dy, epsilon: 1));

    // Back to the title: out of the group, the title selected.
    await pumpCanvas(
      tester,
      document,
      zoom: 2,
      highlights: matches,
      currentHighlight: matches.first,
    );
    await tester.pump();
    expect(harness(tester).selection, {'title'});
  });

  testWidgets('a match in the notes or on another slide reveals nothing', (
    tester,
  ) async {
    final deck = searchDeck();
    final matches = search(deck, 'review');
    final notes = matches.firstWhere((m) => m.field == SlideMatchField.notes);
    await pumpCanvas(
      tester,
      SlideDocumentNotifier(deck),
      highlights: matches,
      currentHighlight: notes,
    );
    await tester.pump();
    expect(harness(tester).selection, isEmpty);
    expect(
      painters(tester).expand((p) => p.highlights).where((h) => h.current),
      isEmpty,
    );
  });
}
