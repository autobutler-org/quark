import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

/// Measures each paragraph as one line of its theme's body size, or 36.
double themedLines(TextBox box, SlideTheme? theme) =>
    box.paragraphs.length * (theme?.body.fontSize ?? 36);

void main() {
  late SlideDocumentController doc;
  var next = 0;
  setUp(() {
    next = 0;
    doc = SlideDocumentController(
      Presentation(slides: [const Slide(id: 's')]),
      newId: () => 'n${++next}',
      measureText: themedLines,
    );
  });

  Slide slide(String id) => doc.presentation.slideById(id)!;
  SlideElement element(String id) => slide('s').elementById(id)!;
  TextBox slotBox(String slideId, String slot) => slide(slideId)
      .elements
      .whereType<TextBox>()
      .singleWhere((b) => b.slot == slot);

  group('setTheme', () {
    test('sets the theme as one undo step', () {
      doc.setTheme(SlideThemes.dark);
      expect(doc.presentation.theme, SlideThemes.dark);
      doc.setTheme(SlideThemes.warm);
      expect(doc.undo(), isTrue);
      expect(doc.presentation.theme, SlideThemes.dark);
      doc.undo();
      expect(doc.presentation.theme, isNull);
      expect(doc.canUndo, isFalse);
    });

    test('setting the theme the deck has records no step', () {
      doc.setTheme(null);
      expect(doc.canUndo, isFalse);
    });

    test('role colors restyle without rewriting the elements', () {
      final id = doc.insertShape('s', ShapeKind.ellipse);
      final before = slide('s').elementById(id);
      doc.setTheme(SlideThemes.dark);
      expect(slide('s').elementById(id), same(before));
      final fill = (before! as ShapeElement).fill!;
      expect(fill.resolve(doc.presentation.theme), 0xFF7AA2FF);
    });

    test('a growing text box refits to the new theme in the same step', () {
      final id = doc.insertTextBox('s', at: (x: 0, y: 0), height: 10);
      expect(slide('s').elementById(id)!.frame.height, 36);
      final big = SlideThemes.light.copyWith(
        body: SlideThemes.light.body.copyWith(fontSize: 72),
      );
      doc.setTheme(big);
      expect(slide('s').elementById(id)!.frame.height, 72);
      doc.undo();
      expect(slide('s').elementById(id)!.frame.height, 36);
    });
  });

  group('theme shape styles', () {
    test('new shapes and lines take the theme\'s styles', () {
      doc.setTheme(SlideThemes.highContrast);
      final shape =
          element(doc.insertShape('s', ShapeKind.rectangle)) as ShapeElement;
      expect(shape.fill, const SlideColor.theme(ThemeColor.accent1));
      expect(shape.stroke, SlideThemes.highContrast.shapes.stroke);
      final line = element(doc.insertLine('s')) as LineElement;
      expect(line.stroke, SlideThemes.highContrast.shapes.line);
    });

    test('without a theme they take the light theme\'s', () {
      final shape =
          element(doc.insertShape('s', ShapeKind.rectangle)) as ShapeElement;
      expect(shape.fill, SlideDocumentController.defaultShapeFill);
      expect(shape.stroke, isNull);
      expect(doc.shapeStyle, SlideThemes.light.shapes);
    });

    test('a fill or stroke given outright wins, null included', () {
      final shape =
          element(doc.insertShape('s', ShapeKind.rectangle, fill: null))
              as ShapeElement;
      expect(shape.fill, isNull);
    });
  });

  group('insertSlideWithLayout', () {
    test('adds a slide with an empty placeholder per slot', () {
      final id = doc.insertSlideWithLayout(SlideLayout.title.id);
      expect(id, 'n1');
      expect(doc.presentation.slides.map((s) => s.id), ['s', 'n1']);
      final added = slide(id);
      expect(added.layoutId, 'title');
      expect(added.elements.map((e) => e.id), ['n2', 'n3']);
      expect(slotBox(id, 'title').textRole, ThemeTextRole.title);
      expect(slotBox(id, 'subtitle').placeholder, 'Click to add subtitle');
      doc.undo();
      expect(doc.presentation.slides.map((s) => s.id), ['s']);
    });

    test('inserts at an index', () {
      doc.insertSlideWithLayout('blank', index: 0);
      expect(doc.presentation.slides.map((s) => s.id), ['n1', 's']);
    });

    test('an unknown layout throws', () {
      expect(
          () => doc.insertSlideWithLayout('comparison'), throwsArgumentError);
      expect(doc.canUndo, isFalse);
    });
  });

  group('setSlideLayout', () {
    test('re-flows the slide, keeps what was typed, as one step', () {
      final id = doc.insertSlideWithLayout('titleAndContent');
      doc.editText(id, slotBox(id, 'body').id, [
        TextParagraph.plain('Point one'),
      ]);
      final before = doc.presentation;
      doc.setSlideLayout(id, 'twoContent');
      expect(slide(id).layoutId, 'twoContent');
      expect(slotBox(id, 'left').plainText, 'Point one');
      expect(slotBox(id, 'right').plainText, isEmpty);
      expect(
        slotBox(id, 'left').frame,
        SlideLayout.twoContent
            .placeholder('left')!
            .frameOn(doc.presentation.size),
      );
      doc.undo();
      expect(doc.presentation, before);
    });

    test('works on a slide made before layouts existed', () {
      doc.addElement(
        's',
        ShapeElement(
          id: 'box',
          frame: ElementFrame(x: 0, y: 0, width: 5, height: 5),
        ),
      );
      doc.setSlideLayout('s', 'title');
      expect(slide('s').elements.map((e) => e.id), ['n1', 'n2', 'box']);
    });

    test('an unknown slide or layout throws', () {
      expect(() => doc.setSlideLayout('s', 'nope'), throwsArgumentError);
      expect(() => doc.setSlideLayout('nope', 'title'), throwsArgumentError);
    });
  });

  group('resetSlideToLayout', () {
    test('puts moved placeholders back as one step', () {
      final id = doc.insertSlideWithLayout('title');
      final title = slotBox(id, 'title');
      doc.moveElements(id, [title.id], 50, 50);
      doc.deleteElements(id, [slotBox(id, 'subtitle').id]);
      doc.resetSlideToLayout(id);
      expect(slotBox(id, 'title').frame, title.frame);
      expect(slotBox(id, 'subtitle').plainText, isEmpty);
      doc.undo();
      expect(slotBox(id, 'title').frame, title.frame.translate(50, 50));
    });

    test('a slide already as its layout defines it records no step', () {
      final id = doc.insertSlideWithLayout('title');
      final before = doc.presentation;
      doc.resetSlideToLayout(id);
      expect(doc.presentation, same(before));
      doc.undo(); // the insertion, not a reset
      expect(doc.presentation.slides.map((s) => s.id), ['s']);
    });
  });
}
