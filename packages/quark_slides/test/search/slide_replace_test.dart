import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

ElementFrame frame() => ElementFrame(x: 0, y: 0, width: 400, height: 100);

/// One slide `s`: a title placeholder `t` (`Big ` bold, `cat` italic,
/// ` sat`), a group `g` holding `inner` (`cat cat`), and notes.
Presentation deck() => Presentation(
      slides: [
        Slide(
          id: 's',
          notes: 'say cat\ncat again',
          elements: [
            TextBox(
              id: 't',
              frame: frame(),
              slot: 'title',
              textRole: ThemeTextRole.title,
              placeholder: 'Click to add title',
              autoFit: TextAutoFit.fixed,
              paragraphs: const [
                TextParagraph([
                  TextRun('Big ', bold: true),
                  TextRun('cat', italic: true),
                  TextRun(' sat'),
                ], alignment: TextAlignment.center),
              ],
            ),
            GroupElement(
              id: 'g',
              frame: frame(),
              children: [
                TextBox(
                  id: 'inner',
                  frame: frame(),
                  autoFit: TextAutoFit.fixed,
                  paragraphs: [TextParagraph.plain('cat cat')],
                ),
              ],
            ),
          ],
        ),
      ],
    );

const _notes = SlideSearchScope(includeNotes: true);

List<SlideMatch> find(Presentation p, String text, {bool notes = true}) =>
    SlideSearch.find(
      p,
      SlideSearchQuery(text),
      scope: notes ? _notes : SlideSearchScope.allSlides,
    ).matches;

TextBox boxOf(SlideDocumentController doc, String id) =>
    doc.presentation.slides.single.findElement(id)! as TextBox;

void main() {
  group('replaceInParagraphs', () {
    final paragraphs = const [
      TextParagraph([
        TextRun('Big ', bold: true),
        TextRun('cat', italic: true),
        TextRun(' sat'),
      ]),
    ];

    SlideMatch match(int start, int end, String text, {int paragraph = 0}) =>
        SlideMatch(
          slideId: 's',
          slideIndex: 0,
          field: SlideMatchField.text,
          elementPath: const ['t'],
          paragraph: paragraph,
          start: start,
          end: end,
          text: text,
        );

    test('the replacement takes the first matched run, spanning runs', () {
      final result =
          replaceInParagraphs(paragraphs, [match(2, 6, 'g ca')], 'X');
      expect(result.count, 1);
      expect(result.paragraphs.single.runs, const [
        TextRun('BiX', bold: true),
        TextRun('t', italic: true),
        TextRun(' sat'),
      ]);
    });

    test('a match inside one run keeps that run whole', () {
      final result =
          replaceInParagraphs(paragraphs, [match(4, 7, 'cat')], 'dog');
      expect(result.paragraphs.single.runs, const [
        TextRun('Big ', bold: true),
        TextRun('dog', italic: true),
        TextRun(' sat'),
      ]);
    });

    test('a replacement styled like its neighbor merges into it', () {
      final result =
          replaceInParagraphs(paragraphs, [match(0, 7, 'Big cat')], 'A');
      expect(result.paragraphs.single.runs, const [
        TextRun('A', bold: true),
        TextRun(' sat'),
      ]);
      final merged =
          replaceInParagraphs(paragraphs, [match(7, 11, ' sat')], 'x');
      expect(merged.paragraphs.single.runs, const [
        TextRun('Big ', bold: true),
        TextRun('cat', italic: true),
        TextRun('x'),
      ]);
    });

    test('an empty replacement deletes', () {
      final result = replaceInParagraphs(paragraphs, [match(3, 7, ' cat')], '');
      expect(result.paragraphs.single.plainText, 'Big sat');
    });

    test('a stale match is skipped', () {
      final result = replaceInParagraphs(paragraphs, [match(4, 7, 'dog')], 'x');
      expect(result.count, 0);
      expect(result.paragraphs, paragraphs);
      expect(
        replaceInParagraphs(paragraphs, [match(0, 3, 'x', paragraph: 3)], 'y')
            .count,
        0,
      );
    });

    test('overlapping matches replace only the later one', () {
      final result = replaceInParagraphs(
        [TextParagraph.plain('aaa')],
        [match(0, 2, 'aa'), match(1, 3, 'aa')],
        'b',
      );
      expect(result.count, 1);
      expect(result.paragraphs.single.plainText, 'ab');
    });

    test('a replacement with a line break splits the paragraph', () {
      final result = replaceInParagraphs(paragraphs, [match(3, 4, ' ')], '\n');
      expect(result.paragraphs.map((p) => p.plainText), ['Big', 'cat sat']);
    });
  });

  group('replaceInNotes', () {
    test('replaces matches across lines', () {
      final matches = find(deck(), 'cat').where(
        (m) => m.field == SlideMatchField.notes,
      );
      final result = replaceInNotes('say cat\ncat again', matches, 'dog');
      expect(result, (notes: 'say dog\ndog again', count: 2));
    });
  });

  group('SlideDocumentController', () {
    test('replaceCurrent replaces one match as one undo step', () {
      final doc = SlideDocumentController(deck());
      final match = find(doc.presentation, 'cat')[1]; // in the group
      expect(doc.replaceCurrent(match, 'dog'), isTrue);
      expect(boxOf(doc, 'inner').plainText, 'dog cat');
      expect(boxOf(doc, 't').plainText, 'Big cat sat');
      doc.undo();
      expect(doc.presentation, deck());
      expect(doc.canUndo, isFalse);
    });

    test('replaceAll replaces boxes, groups and notes as one undo step', () {
      final doc = SlideDocumentController(deck());
      final count = doc.replaceAll(find(doc.presentation, 'cat'), 'dog');
      expect(count, 5);
      final slide = doc.presentation.slides.single;
      expect(boxOf(doc, 't').plainText, 'Big dog sat');
      expect(boxOf(doc, 'inner').plainText, 'dog dog');
      expect(slide.notes, 'say dog\ndog again');
      expect(find(doc.presentation, 'cat'), isEmpty);
      doc.undo();
      expect(doc.presentation, deck());
      expect(doc.canUndo, isFalse);
    });

    test('replacing with text containing the query does not loop', () {
      final doc = SlideDocumentController(deck());
      final before = find(doc.presentation, 'cat').length;
      expect(doc.replaceAll(find(doc.presentation, 'cat'), 'concat'), before);
      expect(boxOf(doc, 'inner').plainText, 'concat concat');
      expect(find(doc.presentation, 'cat').length, before);
    });

    test('placeholder slot, role and prompt are untouched', () {
      final doc = SlideDocumentController(deck());
      doc.replaceAll(find(doc.presentation, 'Big cat sat'), 'Hello');
      final t = boxOf(doc, 't');
      expect(t.plainText, 'Hello');
      expect(t.slot, 'title');
      expect(t.textRole, ThemeTextRole.title);
      expect(t.placeholder, 'Click to add title');
      expect(t.paragraphs.single.alignment, TextAlignment.center);
      expect(t.paragraphs.single.runs, const [TextRun('Hello', bold: true)]);
    });

    test('stale matches replace nothing and record no step', () {
      final doc = SlideDocumentController(deck());
      final matches = find(doc.presentation, 'cat');
      doc.replaceAll(matches, 'dog');
      final steps = doc.canUndo;
      doc.undo();
      doc.editText('s', 'inner', [TextParagraph.plain('no felines')]);
      final stale = matches.where((m) => m.elementId == 'inner').toList();
      expect(doc.replaceAll(stale, 'dog'), 0);
      expect(steps, isTrue);
      doc.undo();
      expect(doc.canUndo, isFalse, reason: 'only the edit was recorded');
    });

    test('matches on a deleted slide are skipped', () {
      final doc = SlideDocumentController(
        Presentation(slides: [...deck().slides, const Slide(id: 'x')]),
      );
      final matches = find(doc.presentation, 'cat');
      doc.deleteSlide('s');
      expect(doc.replaceAll(matches, 'dog'), 0);
    });

    test('a growing box refits after a replace', () {
      final doc = SlideDocumentController(
        Presentation(
          slides: [
            Slide(
              id: 's',
              elements: [
                TextBox(
                  id: 'b',
                  frame: frame(),
                  paragraphs: [TextParagraph.plain('x')],
                ),
              ],
            ),
          ],
        ),
        measureText: (box, _) => box.plainText.length * 50.0,
      );
      doc.replaceAll(find(doc.presentation, 'x'), 'xxxxx');
      expect(boxOf(doc, 'b').frame.height, 250);
    });
  });
}
