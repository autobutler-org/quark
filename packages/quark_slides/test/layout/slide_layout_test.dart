import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

/// Hands out `p1`, `p2`, ... as new ids.
String Function() counter() {
  var next = 0;
  return () => 'p${++next}';
}

TextBox slotBox(Slide slide, String slot) =>
    slide.elements.whereType<TextBox>().singleWhere((b) => b.slot == slot);

final size = SlideSize.widescreen;

void main() {
  group('built-in layouts', () {
    test('the standard master offers five, in picker order', () {
      expect(SlideMaster.standard.layouts.map((l) => l.id), [
        'title',
        'titleAndContent',
        'sectionHeader',
        'twoContent',
        'blank',
      ]);
      expect(SlideMaster.standard.layoutById('twoContent'),
          same(SlideLayout.twoContent));
      expect(SlideMaster.standard.layoutById('comparison'), isNull);
      expect(SlideLayout.blank.placeholders, isEmpty);
    });

    test('every slot fits on the slide, at 16:9 and 4:3', () {
      for (final slideSize in [SlideSize.widescreen, SlideSize.standard]) {
        for (final layout in SlideMaster.standard.layouts) {
          for (final p in layout.placeholders) {
            final f = p.frameOn(slideSize);
            expect(f.x, greaterThanOrEqualTo(0));
            expect(f.y, greaterThanOrEqualTo(0));
            expect(f.x + f.width, lessThanOrEqualTo(slideSize.width));
            expect(f.y + f.height, lessThanOrEqualTo(slideSize.height));
            expect(p.prompt, isNotEmpty);
          }
        }
      }
    });

    test('each layout has one title, and the right content slots', () {
      List<String> slots(SlideLayout l) =>
          [for (final p in l.placeholders) p.id];
      expect(slots(SlideLayout.title), ['title', 'subtitle']);
      expect(slots(SlideLayout.titleAndContent), ['title', 'body']);
      expect(slots(SlideLayout.sectionHeader), ['title', 'subtitle']);
      expect(slots(SlideLayout.twoContent), ['title', 'left', 'right']);
    });

    test('a slot makes an empty box carrying its slot, role and prompt', () {
      final p = SlideLayout.title.placeholder('title')!;
      final box = p.emptyBox('b', size);
      expect(box.slot, 'title');
      expect(box.textRole, ThemeTextRole.title);
      expect(box.placeholder, 'Click to add title');
      expect(box.frame, p.frameOn(size));
      expect(box.anchor, TextAnchor.bottom);
      expect(box.paragraphs.single.alignment, TextAlignment.center);
      expect(box.plainText, isEmpty);
    });
  });

  group('applyLayout', () {
    Slide built(SlideLayout layout) => Slide(
          id: 's',
          layoutId: layout.id,
          elements: layoutBoxes(layout, size, counter()),
        );

    Slide typed(Slide slide, String slot, String text) => slide.copyWith(
          elements: [
            for (final e in slide.elements)
              e is TextBox && e.slot == slot
                  ? e.copyWith(paragraphs: [TextParagraph.plain(text)])
                  : e,
          ],
        );

    test('an untouched placeholder re-flows into its new slot', () {
      final slide = typed(built(SlideLayout.title), 'title', 'Q3');
      final next = applyLayout(
        slide,
        SlideLayout.titleAndContent,
        size,
        counter(),
      );
      expect(next.layoutId, 'titleAndContent');
      final title = slotBox(next, 'title');
      expect(title.plainText, 'Q3');
      expect(title.frame,
          SlideLayout.titleAndContent.placeholder('title')!.frameOn(size));
      expect(title.anchor, TextAnchor.middle);
      expect(title.paragraphs.single.alignment, TextAlignment.start);
      expect(title.id, slotBox(slide, 'title').id);
    });

    test('a placeholder the user moved keeps its place, not its anchor', () {
      var slide = typed(built(SlideLayout.title), 'title', 'Q3');
      final moved = slotBox(slide, 'title').frame.translate(40, 40);
      slide = slide.copyWith(elements: [
        for (final e in slide.elements)
          e.id == slotBox(slide, 'title').id ? e.withFrame(moved) : e,
      ]);
      final next = applyLayout(
        slide,
        SlideLayout.titleAndContent,
        size,
        counter(),
      );
      expect(slotBox(next, 'title').frame, moved);
      // Each property inherits on its own: the anchor was never changed.
      expect(slotBox(next, 'title').anchor, TextAnchor.middle);
    });

    test('slots fill by id, then by role', () {
      final slide = typed(
        built(SlideLayout.titleAndContent),
        'body',
        'Point one',
      );
      final next = applyLayout(slide, SlideLayout.twoContent, size, counter());
      expect(slotBox(next, 'left').plainText, 'Point one');
      expect(slotBox(next, 'left').id, slotBox(slide, 'body').id);
      expect(slotBox(next, 'right').plainText, isEmpty);
      expect(slotBox(next, 'right').id, 'p1');
    });

    test('typed text with no slot left is kept as an ordinary text box', () {
      final slide = typed(
        typed(built(SlideLayout.twoContent), 'left', 'Pros'),
        'right',
        'Cons',
      );
      final next = applyLayout(
        slide,
        SlideLayout.titleAndContent,
        size,
        counter(),
      );
      expect(slotBox(next, 'body').plainText, 'Pros');
      final kept = next.elements
          .whereType<TextBox>()
          .singleWhere((b) => b.plainText == 'Cons');
      expect(kept.slot, isNull);
      expect(kept.placeholder, isEmpty);
      expect(kept.frame, slotBox(slide, 'right').frame);
    });

    test('an empty placeholder with no slot left goes', () {
      final slide = built(SlideLayout.title);
      final next = applyLayout(slide, SlideLayout.blank, size, counter());
      expect(next.elements, isEmpty);
      expect(next.layoutId, 'blank');
    });

    test('other elements stay where they are in the stacking order', () {
      final shape = ShapeElement(
        id: 'shape',
        frame: ElementFrame(x: 0, y: 0, width: 10, height: 10),
      );
      final slide = Slide(id: 's', elements: [shape]);
      final next = applyLayout(slide, SlideLayout.title, size, counter());
      expect(next.elements.map((e) => e.id), ['p1', 'p2', 'shape']);
      expect(next.elements.last, same(shape));
    });

    test('moving onto the same layout changes nothing', () {
      final slide = typed(built(SlideLayout.twoContent), 'left', 'A');
      expect(
        applyLayout(slide, SlideLayout.twoContent, size, counter()),
        slide,
      );
    });
  });

  group('resetToLayout', () {
    test('puts placeholders back and drops their own styles', () {
      final layout = SlideLayout.titleAndContent;
      final title = layout.placeholder('title')!.emptyBox('t', size).copyWith(
        frame: ElementFrame(x: 1, y: 2, width: 300, height: 40, rotation: 5),
        anchor: TextAnchor.bottom,
        paragraphs: const [
          TextParagraph(
            [
              TextRun(
                'Big',
                bold: true,
                fontSize: 99,
                fontFamily: 'Comic',
                color: SlideColor(0xFFFF0000),
              ),
            ],
            alignment: TextAlignment.end,
          ),
        ],
      );
      final slide = Slide(id: 's', layoutId: layout.id, elements: [title]);
      final reset = resetToLayout(slide, size, counter());
      final box = slotBox(reset, 'title');
      expect(box.frame, layout.placeholder('title')!.frameOn(size));
      expect(box.anchor, TextAnchor.middle);
      final paragraph = box.paragraphs.single;
      expect(paragraph.alignment, TextAlignment.start);
      expect(paragraph.runs.single, const TextRun('Big', bold: true));
      // The deleted body slot comes back, empty, at the back.
      expect(reset.elements.first, isA<TextBox>());
      expect((reset.elements.first as TextBox).slot, 'body');
      expect(reset.elements.first.id, 'p1');
    });

    test('a slide whose layout is unknown is left alone', () {
      const slide = Slide(id: 's', layoutId: 'comparison');
      expect(resetToLayout(slide, size, counter()), same(slide));
    });
  });
}
