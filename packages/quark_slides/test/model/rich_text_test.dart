import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

/// `Hello, world` with `world` bold, then a centered bullet `Second`.
List<TextParagraph> sample() => const [
      TextParagraph([TextRun('Hello, '), TextRun('world', bold: true)]),
      TextParagraph(
        [TextRun('Second', fontSize: 40)],
        alignment: TextAlignment.center,
        list: TextListStyle.bullet,
      ),
    ];

String plain(List<TextParagraph> paragraphs) =>
    paragraphs.map((p) => p.plainText).join('\n');

void main() {
  group('replaceText', () {
    test('typing takes the style of the character before the caret', () {
      final result = replaceText(sample(), 12, 12, '!');
      expect(result.first.runs, const [
        TextRun('Hello, '),
        TextRun('world!', bold: true),
      ]);
    });

    test('typing at a run boundary takes the earlier run', () {
      final result = replaceText(sample(), 7, 7, 'big ');
      expect(result.first.runs, const [
        TextRun('Hello, big '),
        TextRun('world', bold: true),
      ]);
    });

    test('typing at the start of a paragraph takes the first run', () {
      final result = replaceText(sample(), 13, 13, '2nd ');
      expect(result[1].runs, const [TextRun('2nd Second', fontSize: 40)]);
    });

    test('an explicit style wins and splits the run', () {
      final result = replaceText(
        sample(),
        2,
        2,
        'XX',
        style: const TextRun('ignored', italic: true),
      );
      expect(result.first.runs, const [
        TextRun('He'),
        TextRun('XX', italic: true),
        TextRun('llo, '),
        TextRun('world', bold: true),
      ]);
    });

    test('replacing a selection across runs merges what is left', () {
      final result = replaceText(sample(), 5, 7, '');
      expect(result.first.runs, const [
        TextRun('Hello'),
        TextRun('world', bold: true),
      ]);
      final merged = replaceText(
        const [
          TextParagraph([TextRun('a'), TextRun('b', bold: true), TextRun('c')]),
        ],
        1,
        2,
        '',
      );
      expect(merged.single.runs, const [TextRun('ac')]);
    });

    test('a line break splits the paragraph and keeps its style', () {
      final result = replaceText(sample(), 16, 16, '\n');
      expect(result.map((p) => p.plainText), ['Hello, world', 'Sec', 'ond']);
      expect(result[1].runs, const [TextRun('Sec', fontSize: 40)]);
      expect(result[2].runs, const [TextRun('ond', fontSize: 40)]);
      for (final p in result.skip(1)) {
        expect(p.alignment, TextAlignment.center);
        expect(p.list, TextListStyle.bullet);
      }
    });

    test('pasting several lines makes several paragraphs', () {
      final result = replaceText(sample(), 0, 0, 'a\nb\nc');
      expect(plain(result), 'a\nb\ncHello, world\nSecond');
      expect(result.length, 4);
    });

    test('deleting a line break joins paragraphs with the first one style', () {
      final result = replaceText(sample(), 12, 13, '');
      expect(result.single.plainText, 'Hello, worldSecond');
      expect(result.single.alignment, TextAlignment.start);
      expect(result.single.list, TextListStyle.none);
      expect(result.single.runs.last, const TextRun('Second', fontSize: 40));
    });

    test('deleting everything remembers the style typing starts with', () {
      final result = replaceText(
        const [
          TextParagraph([TextRun('Title', fontSize: 72, bold: true)]),
        ],
        0,
        5,
        '',
      );
      expect(result.single.plainText, '');
      expect(result.single.runs, const [
        TextRun('', fontSize: 72, bold: true),
      ]);
      final typed = replaceText(result, 0, 0, 'New');
      expect(typed.single.runs, const [
        TextRun('New', fontSize: 72, bold: true),
      ]);
    });

    test('an unstyled empty paragraph keeps no runs', () {
      final result = replaceText([TextParagraph.plain('abc')], 0, 3, '');
      expect(result.single, TextParagraph.plain(''));
    });

    test('an empty box gets a first paragraph', () {
      expect(replaceText(const [], 0, 0, 'Hi'), [TextParagraph.plain('Hi')]);
    });

    test('offsets out of range are clamped', () {
      final result = replaceText(sample(), 50, 99, '!');
      expect(plain(result), 'Hello, world\nSecond!');
    });

    test('unknown fields survive on split runs and paragraphs', () {
      const paragraphs = [
        TextParagraph(
          [
            TextRun('abcd', extra: {'highlight': '#FF0'}),
          ],
          extra: {'spacingAfter': 12},
        ),
      ];
      final result = replaceText(paragraphs, 2, 2, '\n');
      for (final p in result) {
        expect(p.extra, {'spacingAfter': 12});
        expect(p.runs.single.extra, {'highlight': '#FF0'});
      }
      final styled = formatParagraphs(
        paragraphs,
        const TextFormat(bold: true),
        start: 1,
        end: 3,
      );
      expect(
          styled.single.runs.map((r) => r.extra),
          everyElement({
            'highlight': '#FF0',
          }));
      expect(styled.single.runs.length, 3);
    });

    test('runs with different unknown fields are not merged', () {
      final result = replaceText(
        const [
          TextParagraph([
            TextRun('a', extra: {'x': 1}),
            TextRun('b'),
            TextRun('c'),
          ]),
        ],
        1,
        2,
        '',
      );
      expect(result.single.runs, const [
        TextRun('a', extra: {'x': 1}),
        TextRun('c'),
      ]);
    });
  });

  group('formatParagraphs', () {
    test('styles a selection inside one run by splitting it', () {
      final result = formatParagraphs(
        sample(),
        const TextFormat(italic: true),
        start: 1,
        end: 4,
      );
      expect(result.first.runs, const [
        TextRun('H'),
        TextRun('ell', italic: true),
        TextRun('o, '),
        TextRun('world', bold: true),
      ]);
      expect(result[1], sample()[1]);
    });

    test('styles across paragraphs', () {
      final result = formatParagraphs(
        sample(),
        const TextFormat(underline: true),
        start: 10,
        end: 16,
      );
      expect(result.first.runs, const [
        TextRun('Hello, '),
        TextRun('wor', bold: true),
        TextRun('ld', bold: true, underline: true),
      ]);
      expect(result[1].runs, const [
        TextRun('Sec', fontSize: 40, underline: true),
        TextRun('ond', fontSize: 40),
      ]);
    });

    test('styling the whole run merges neighbors that now match', () {
      final result = formatParagraphs(
        sample(),
        const TextFormat(bold: true),
        start: 0,
        end: 7,
      );
      expect(result.first.runs, const [TextRun('Hello, world', bold: true)]);
    });

    test('with no range it styles everything', () {
      final result = formatParagraphs(
        sample(),
        const TextFormat(
          strikethrough: true,
          fontSize: 24.0,
          fontFamily: 'Inter',
          color: SlideColor.white,
        ),
      );
      for (final run in result.expand((p) => p.runs)) {
        expect(run.strikethrough, isTrue);
        expect(run.fontSize, 24);
        expect(run.fontFamily, 'Inter');
        expect(run.color, SlideColor.white);
      }
      expect(result.first.runs.length, 2, reason: 'bold still differs');
    });

    test('null makes a style inherit again', () {
      final result = formatParagraphs(
        sample(),
        const TextFormat(fontSize: null),
      );
      expect(result[1].runs, const [TextRun('Second')]);
    });

    test('a collapsed selection leaves runs alone', () {
      final result = formatParagraphs(
        sample(),
        const TextFormat(bold: true),
        start: 3,
        end: 3,
      );
      expect(result, sample());
    });

    test('a collapsed selection in an empty paragraph sets its typing style',
        () {
      final result = formatParagraphs(
        [TextParagraph.plain('')],
        const TextFormat(fontSize: 60.0),
        start: 0,
        end: 0,
      );
      expect(result.single.runs, const [TextRun('', fontSize: 60)]);
      expect(
        replaceText(result, 0, 0, 'x').single.runs,
        const [TextRun('x', fontSize: 60)],
      );
    });

    test('paragraph fields reach every paragraph the selection touches', () {
      final result = formatParagraphs(
        sample(),
        const TextFormat(
          alignment: TextAlignment.end,
          lineSpacing: 1.5,
          list: TextListStyle.numbered,
        ),
        start: 3,
        end: 3,
      );
      expect(result.first.alignment, TextAlignment.end);
      expect(result.first.lineSpacing, 1.5);
      expect(result.first.list, TextListStyle.numbered);
      expect(result[1], sample()[1]);
      final both = formatParagraphs(
        sample(),
        const TextFormat(alignment: TextAlignment.end),
        start: 3,
        end: 14,
      );
      expect(both.map((p) => p.alignment), everyElement(TextAlignment.end));
    });

    test('lineSpacing null restores the default', () {
      final result = formatParagraphs(
        const [
          TextParagraph([TextRun('a')], lineSpacing: 2)
        ],
        const TextFormat(lineSpacing: null),
      );
      expect(result.single.lineSpacing, isNull);
    });
  });

  group('formatTextBox', () {
    final box = TextBox(
      id: 't',
      frame: ElementFrame(x: 0, y: 0, width: 100, height: 100),
      paragraphs: sample(),
    );

    test('box fields change the box, run fields the text', () {
      final result = formatTextBox(
        box,
        const TextFormat(
          anchor: TextAnchor.bottom,
          autoFit: TextAutoFit.shrink,
          italic: true,
        ),
      );
      expect(result.anchor, TextAnchor.bottom);
      expect(result.autoFit, TextAutoFit.shrink);
      expect(result.paragraphs.expand((p) => p.runs).every((r) => r.italic),
          isTrue);
    });

    test('a box-only format leaves the paragraphs identical', () {
      final result =
          formatTextBox(box, const TextFormat(anchor: TextAnchor.middle));
      expect(identical(result.paragraphs, box.paragraphs), isTrue);
    });
  });

  group('textFormatOf', () {
    test('a uniform selection reports its values', () {
      final format = textFormatOf(sample(), start: 13, end: 19);
      expect(format.bold, isFalse);
      expect(format.fontSize, 40);
      expect(format.fontFamily, isNull);
      expect(format.alignment, TextAlignment.center);
      expect(format.list, TextListStyle.bullet);
      expect(format.lineSpacing, isNull);
    });

    test('a mixed selection leaves the mixed fields out', () {
      final format = textFormatOf(sample());
      expect(format.bold, isNull);
      expect(format.italic, isFalse);
      expect(format.fontSize, same(unset));
      expect(format.alignment, isNull);
      expect(format.list, isNull);
    });

    test('a collapsed selection reports the typing style', () {
      expect(textFormatOf(sample(), start: 12, end: 12).bold, isTrue);
      expect(textFormatOf(sample(), start: 7, end: 7).bold, isFalse);
      expect(
        textFormatOf(
          const [
            TextParagraph([TextRun('', fontSize: 9)])
          ],
          start: 0,
          end: 0,
        ).fontSize,
        9,
      );
    });

    test('a box fills in the box fields', () {
      final box = TextBox(
        id: 't',
        frame: ElementFrame(x: 0, y: 0, width: 1, height: 1),
        anchor: TextAnchor.middle,
      );
      final format = textFormatOf(const [], box: box);
      expect(format.anchor, TextAnchor.middle);
      expect(format.autoFit, TextAutoFit.grow);
    });
  });

  group('TextToggle', () {
    test('turns on unless all of the selection has it', () {
      final mixed = textFormatOf(sample());
      expect(TextToggle.bold.changeFrom(mixed), const TextFormat(bold: true));
      final allBold = textFormatOf(sample(), start: 7, end: 12);
      expect(TextToggle.bold.isOn(allBold), isTrue);
      expect(
        TextToggle.bold.changeFrom(allBold),
        const TextFormat(bold: false),
      );
    });

    test('list toggles switch between kinds and off', () {
      final bullet = textFormatOf(sample(), start: 14, end: 14);
      expect(
        TextToggle.bulletList.changeFrom(bullet).list,
        TextListStyle.none,
      );
      expect(
        TextToggle.numberedList.changeFrom(bullet).list,
        TextListStyle.numbered,
      );
      for (final toggle in TextToggle.values) {
        final on = toggle.changeFrom(const TextFormat());
        expect(toggle.isOn(on), isTrue, reason: toggle.name);
      }
    });
  });

  group('TextFormat', () {
    test('merge lays set fields over the others', () {
      const a = TextFormat(bold: true, fontSize: 10.0);
      const b = TextFormat(italic: true, fontSize: null);
      expect(
        a.merge(b),
        const TextFormat(bold: true, italic: true, fontSize: null),
      );
      expect(a.merge(const TextFormat()), a);
    });

    test('reports which levels it changes', () {
      expect(const TextFormat().changesRuns, isFalse);
      expect(const TextFormat(color: null).changesRuns, isTrue);
      expect(const TextFormat(lineSpacing: null).changesParagraphs, isTrue);
      expect(const TextFormat(autoFit: TextAutoFit.fixed).changesBox, isTrue);
      expect(const TextFormat(bold: true).toString(), 'TextFormat(bold: true)');
    });
  });

  test('typingStyleAt reads the style before the offset', () {
    expect(typingStyleAt(sample(), 12), const TextRun('', bold: true));
    expect(typingStyleAt(sample(), 13), const TextRun('', fontSize: 40));
    expect(typingStyleAt(sample(), 99), const TextRun('', fontSize: 40));
    expect(typingStyleAt(const [], 0), const TextRun(''));
  });

  test('listMarkers numbers unbroken runs of numbered paragraphs', () {
    const n = TextParagraph([], list: TextListStyle.numbered);
    const b = TextParagraph([], list: TextListStyle.bullet);
    const p = TextParagraph([]);
    expect(listMarkers(const [n, n, p, n, b, n, n]), [
      '1.',
      '2.',
      null,
      '1.',
      '•',
      '1.',
      '2.',
    ]);
  });
}
