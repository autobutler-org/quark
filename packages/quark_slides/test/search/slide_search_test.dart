import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

ElementFrame frame([double y = 0]) =>
    ElementFrame(x: 0, y: y, width: 400, height: 100);

TextBox box(String id, List<TextParagraph> paragraphs, {double y = 0}) =>
    TextBox(id: id, frame: frame(y), paragraphs: paragraphs);

/// Two slides. `s1`: a title `t` (`Cat and cat` with `and cat` bold), a
/// shape, and a group `g` holding a group `h` holding the box `deep`
/// (`a cat`), with notes `Cat notes\nmore cat`. `s2`: a box `u` (`concat`).
Presentation deck() => Presentation(
      slides: [
        Slide(
          id: 's1',
          notes: 'Cat notes\nmore cat',
          elements: [
            box('t', const [
              TextParagraph([TextRun('Cat '), TextRun('and cat', bold: true)]),
            ]),
            ShapeElement(id: 'shape', frame: frame(200)),
            GroupElement(
              id: 'g',
              frame: frame(300),
              children: [
                GroupElement(
                  id: 'h',
                  frame: frame(),
                  children: [
                    box('deep', [TextParagraph.plain('a cat')]),
                  ],
                ),
              ],
            ),
          ],
        ),
        Slide(
          id: 's2',
          elements: [
            box('u', [TextParagraph.plain('concat')]),
          ],
        ),
      ],
    );

List<String> describe(SlideSearchResult result) => [
      for (final m in result.matches)
        '${m.slideId}:${m.field.name}:${m.elementPath.join('/')}:'
            '${m.paragraph}:${m.start}-${m.end}',
    ];

SlideSearchResult find(
  Presentation p,
  String text, {
  bool caseSensitive = false,
  bool wholeWord = false,
  bool regex = false,
  SlideSearchScope scope = SlideSearchScope.allSlides,
}) =>
    SlideSearch.find(
      p,
      SlideSearchQuery(
        text,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        regex: regex,
      ),
      scope: scope,
    );

void main() {
  group('SlideSearch.find', () {
    test('finds text in reading order, inside nested groups', () {
      expect(describe(find(deck(), 'cat')), [
        's1:text:t:0:0-3',
        's1:text:t:0:8-11',
        's1:text:g/h/deep:0:2-5',
        's2:text:u:0:3-6',
      ]);
    });

    test('matches are sorted by compareTo', () {
      final matches = find(deck(), 'cat').matches;
      expect([...matches]..sort(), matches);
    });

    test('an empty query finds nothing and is no error', () {
      final result = find(deck(), '');
      expect(result.matches, isEmpty);
      expect(result.error, isNull);
    });

    test('case sensitivity', () {
      expect(find(deck(), 'Cat', caseSensitive: true).length, 1);
      expect(find(deck(), 'Cat').length, 4);
    });

    test('whole word skips a match inside a word', () {
      expect(
        describe(find(deck(), 'cat', wholeWord: true)),
        isNot(contains('s2:text:u:0:3-6')),
      );
      expect(find(deck(), 'cat', wholeWord: true).length, 3);
    });

    test('whole word knows letters beyond ASCII', () {
      final p = Presentation(
        slides: [
          Slide(
            id: 's',
            elements: [
              box('b', [TextParagraph.plain('café cafés naïve')]),
            ],
          ),
        ],
      );
      expect(describe(find(p, 'café', wholeWord: true)), ['s:text:b:0:0-4']);
      expect(describe(find(p, 'NAÏVE', wholeWord: true)), ['s:text:b:0:11-16']);
    });

    test('a match spans runs of different styles', () {
      final m = find(deck(), 'cat and').matches.single;
      expect((m.elementId, m.start, m.end, m.text), ('t', 0, 7, 'Cat and'));
    });

    test('a match never spans a paragraph break', () {
      final p = Presentation(
        slides: [
          Slide(
            id: 's',
            elements: [
              box('b', [TextParagraph.plain('ab'), TextParagraph.plain('cd')]),
            ],
          ),
        ],
      );
      expect(find(p, 'bc').matches, isEmpty);
      expect(find(p, 'b\ncd').matches, isEmpty);
      expect(describe(find(p, 'cd')), ['s:text:b:1:0-2']);
    });

    test('matches do not overlap', () {
      final p = Presentation(
        slides: [
          Slide(
            id: 's',
            elements: [
              box('b', [TextParagraph.plain('aaaa a')]),
            ],
          ),
        ],
      );
      expect(describe(find(p, 'aa')), ['s:text:b:0:0-2', 's:text:b:0:2-4']);
      expect(describe(find(p, 'aaa')), ['s:text:b:0:0-3']);
    });

    test('offsets count UTF-16 units through emoji and accents', () {
      final p = Presentation(
        slides: [
          Slide(
            id: 's',
            elements: [
              box('b', const [
                TextParagraph(
                    [TextRun('😀 '), TextRun('naïve 😀', bold: true)]),
              ]),
            ],
          ),
        ],
      );
      expect(describe(find(p, '😀')), ['s:text:b:0:0-2', 's:text:b:0:9-11']);
      expect(describe(find(p, 'NAÏVE')), ['s:text:b:0:3-8']);
      expect(find(p, '.', regex: true).length, 9, reason: 'emoji is one');
    });

    test('notes are searched only when the scope says so', () {
      expect(describe(find(deck(), 'notes')), isEmpty);
      final scope = const SlideSearchScope(includeNotes: true);
      expect(describe(find(deck(), 'cat', scope: scope)), [
        's1:text:t:0:0-3',
        's1:text:t:0:8-11',
        's1:text:g/h/deep:0:2-5',
        's1:notes::0:0-3',
        's1:notes::1:5-8',
        's2:text:u:0:3-6',
      ]);
    });

    test('a slide scope searches one slide', () {
      final scope = const SlideSearchScope(slideId: 's2');
      expect(describe(find(deck(), 'cat', scope: scope)), ['s2:text:u:0:3-6']);
    });

    test('an empty placeholder is not searched for its prompt', () {
      final p = Presentation(
        slides: [
          Slide(
            id: 's',
            elements: [
              TextBox(
                id: 'b',
                frame: frame(),
                placeholder: 'Click to add title',
                slot: 'title',
              ),
            ],
          ),
        ],
      );
      expect(find(p, 'title').matches, isEmpty);
    });

    test('the match carries its path and parent group', () {
      final m = find(deck(), 'a cat').matches.single;
      expect(m.elementPath, ['g', 'h', 'deep']);
      expect(m.elementId, 'deep');
      expect(m.groupId, 'h');
      expect(find(deck(), 'Cat and').matches.single.groupId, isNull);
    });
  });

  group('regular expressions', () {
    test('are off by default: special characters are literal', () {
      final p = Presentation(
        slides: [
          Slide(
            id: 's',
            elements: [
              box('b', [TextParagraph.plain(r'cost: $5.00 (a+b)')]),
            ],
          ),
        ],
      );
      expect(describe(find(p, r'$5.00')), ['s:text:b:0:6-11']);
      expect(describe(find(p, '(a+b)')), ['s:text:b:0:12-17']);
      expect(find(p, '.').length, 1);
    });

    test('match when switched on', () {
      expect(describe(find(deck(), r'c\w+t', regex: true)), [
        's1:text:t:0:0-3',
        's1:text:t:0:8-11',
        's1:text:g/h/deep:0:2-5',
        's2:text:u:0:0-6',
      ]);
    });

    test('anchors apply per paragraph', () {
      expect(describe(find(deck(), r'^cat', regex: true)), ['s1:text:t:0:0-3']);
    });

    test('an invalid pattern is an error, not a throw', () {
      for (final bad in ['(', '[a', 'a)(b', r'\']) {
        final result = find(deck(), bad, regex: true);
        expect(result.error, SlideSearchError.invalidPattern, reason: bad);
        expect(result.matches, isEmpty);
      }
    });

    test('a catastrophic pattern is refused before it runs', () {
      for (final bad in [
        '(a+)+',
        '(a*)*b',
        r'(\w+\s?)*$',
        '(?:x{2,})+',
        '((ab)+c)*',
        '([a-z]+)*',
      ]) {
        expect(
          find(deck(), bad, regex: true).error,
          SlideSearchError.unsafePattern,
          reason: bad,
        );
      }
    });

    test('ordinary repetition is allowed', () {
      for (final ok in [
        'a+',
        '(ab)+',
        '(a|b)*',
        '(a+)?',
        '(a{2})+',
        r'\(a+\)+'
      ]) {
        expect(SlideSearchQuery.repeatsRepetition(ok), isFalse, reason: ok);
      }
    });

    test('an overlong pattern is refused', () {
      final long = 'a' * (SlideSearchQuery.maxPatternLength + 1);
      expect(find(deck(), long, regex: true).error,
          SlideSearchError.unsafePattern);
    });

    test('empty matches are skipped', () {
      expect(find(deck(), 'x*', regex: true).matches, isEmpty);
      expect(describe(find(deck(), 'cat|x*', regex: true)).length, 4);
    });

    test('whole word wraps a regular expression too', () {
      expect(find(deck(), 'c.t', regex: true, wholeWord: true).length, 3);
    });
  });

  test('a search stops at maxMatches and says it was truncated', () {
    final p = Presentation(
      slides: [
        Slide(
          id: 's',
          elements: [
            box('b', [TextParagraph.plain('a' * (SlideSearch.maxMatches + 5))]),
          ],
        ),
      ],
    );
    final result = find(p, 'a');
    expect(result.length, SlideSearch.maxMatches);
    expect(result.truncated, isTrue);
    expect(find(deck(), 'cat').truncated, isFalse);
  });

  group('navigation', () {
    final result = find(deck(), 'cat');

    test('next and previous wrap', () {
      expect(result.next(null), 0);
      expect(result.next(0), 1);
      expect(result.next(3), 0);
      expect(result.previous(null), 3);
      expect(result.previous(0), 3);
      expect(result.previous(2), 1);
    });

    test('nothing to step through without matches', () {
      expect(SlideSearchResult.empty.next(null), isNull);
      expect(SlideSearchResult.empty.previous(2), isNull);
    });

    test('indexFrom picks up at or after a match, wrapping', () {
      final third = result.matches[2];
      expect(result.indexFrom(third), 2);
      final pastEnd = SlideMatch(
        slideId: 's9',
        slideIndex: 9,
        field: SlideMatchField.text,
        paragraph: 0,
        start: 0,
        end: 1,
        text: 'x',
      );
      expect(result.indexFrom(pastEnd), 0);
    });
  });
}
