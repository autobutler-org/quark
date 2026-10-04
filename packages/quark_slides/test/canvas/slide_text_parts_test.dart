import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_slides/src/canvas/slide_paragraph_editing_controller.dart';

void main() {
  group('SlideParagraphEditingController', () {
    late List<(int, int, String)> edits;
    SlideParagraphEditingController make(String text, {bool lead = false}) {
      edits = [];
      return SlideParagraphEditingController(
        paragraph: TextParagraph.plain(text),
        leadingBreak: lead,
        layout: const SlideTextLayout(),
        onEdit: (start, end, inserted, value) =>
            edits.add((start, end, inserted)),
      );
    }

    test('a paragraph after the first starts with the line-break mark', () {
      final c = make('abc', lead: true);
      expect(c.text, '${SlideParagraphEditingController.lineBreak}abc');
      expect(c.lead, 1);
      expect(make('abc').text, 'abc');
    });

    test('reports typing where the caret is, even beside a twin letter', () {
      final c = make('aa');
      c.value = const TextEditingValue(
        text: 'aaa',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(edits, [(0, 0, 'a')]);
      expect(c.text, 'aa', reason: 'the owner applies edits through sync');
    });

    test('reports a replaced selection and a deletion', () {
      final c = make('hello world');
      c.value = const TextEditingValue(
        text: 'hello there',
        selection: TextSelection.collapsed(offset: 11),
      );
      c.value = const TextEditingValue(
        text: 'hell world',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(edits, [(6, 11, 'there'), (4, 5, '')]);
    });

    test('deleting the line-break mark is an edit at offset 0', () {
      final c = make('abc', lead: true);
      c.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(edits, [(0, 1, '')]);
    });

    test('selection changes pass through, echoes are not news', () {
      final moves = <TextSelection>[];
      final c = make('abc')..onSelectionChanged = moves.add;
      const caret = TextSelection.collapsed(offset: 2);
      c.selection = caret;
      c.selection = caret;
      expect(c.selection, caret);
      expect(moves, [caret]);
    });

    testWidgets('draws the runs and underlines the composing range',
        (tester) async {
      final c = SlideParagraphEditingController(
        paragraph: const TextParagraph([
          TextRun('ab', bold: true),
          TextRun('cd', strikethrough: true),
        ]),
        leadingBreak: false,
        layout: const SlideTextLayout(),
      );
      c.sync(
        c.paragraph,
        leadingBreak: false,
        selection: const TextSelection.collapsed(offset: 3),
        composing: const TextRange(start: 1, end: 3),
      );
      late TextSpan span;
      await tester.pumpWidget(Builder(builder: (context) {
        span = c.buildTextSpan(context: context, withComposing: true);
        return const SizedBox();
      }));
      final parts = span.children!.cast<TextSpan>();
      expect(parts.map((p) => p.text), ['a', 'b', 'c', 'd']);
      expect(parts[0].style!.fontWeight, FontWeight.bold);
      expect(parts[1].style!.decoration, TextDecoration.underline);
      expect(parts[3].style!.decoration, TextDecoration.lineThrough);
      expect(span.toPlainText(), 'abcd');
    });
  });

  group('SlideTextLayout', () {
    const layout = SlideTextLayout();
    TextBox box(int lines, {TextAutoFit fit = TextAutoFit.shrink}) => TextBox(
          id: 't',
          frame: ElementFrame(x: 0, y: 0, width: 400, height: 100),
          paragraphs: List.filled(lines, TextParagraph.plain('line')),
          autoFit: fit,
        );

    test('measures a line per paragraph at the default size', () {
      expect(layout.contentHeight(box(1)), closeTo(36 * 1.2, 2));
      expect(
        layout.contentHeight(box(3)),
        closeTo(3 * layout.contentHeight(box(1)), 0.01),
      );
    });

    test('line spacing and list markers take part in the measure', () {
      final spaced = box(1).copyWith(paragraphs: const [
        TextParagraph([TextRun('x')], lineSpacing: 2),
      ]);
      expect(layout.contentHeight(spaced), closeTo(72, 2));
      final listed = box(1).copyWith(paragraphs: const [
        TextParagraph([TextRun('x')], list: TextListStyle.bullet),
      ]);
      expect(layout.markerWidth(listed.paragraphs.single), 54);
      expect(layout.contentHeight(listed), closeTo(36 * 1.2, 2));
    });

    test('shrinks text that overflows a shrinking box until it fits', () {
      expect(layout.shrinkScale(box(2)), 1);
      final tall = box(6);
      final scale = layout.shrinkScale(tall);
      expect(scale, lessThan(1));
      expect(layout.contentHeight(tall, scale: scale), lessThanOrEqualTo(100));
      expect(layout.shrinkScale(box(6, fit: TextAutoFit.fixed)), 1);
      expect(
        layout.shrinkScale(box(500)),
        SlideTextLayout.minShrinkScale,
      );
    });

    testWidgets('a shrinking box draws its text smaller', (tester) async {
      final tall = box(6);
      await tester.pumpWidget(
        MaterialApp(
          home: SlideCanvas.readOnly(
            slide: Slide(id: 's', elements: [tall]),
            size: SlideSize.widescreen,
          ),
        ),
      );
      final text = tester.widget<RichText>(find.byType(RichText).first);
      expect(
        (text.text as TextSpan).style!.fontSize,
        closeTo(36 * layout.shrinkScale(tall), 0.01),
      );
    });
  });
}
