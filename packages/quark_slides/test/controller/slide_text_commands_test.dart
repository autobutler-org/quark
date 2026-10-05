import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

/// A deck with one slide `s`: text boxes `a` (`Hello`) and `b` (`World`,
/// fixed size), and a shape `c`, each 200 by 50.
Presentation deck() => Presentation(
      slides: [
        Slide(
          id: 's',
          elements: [
            TextBox(
              id: 'a',
              frame: ElementFrame(x: 0, y: 0, width: 200, height: 50),
              paragraphs: [TextParagraph.plain('Hello')],
            ),
            TextBox(
              id: 'b',
              frame: ElementFrame(x: 0, y: 100, width: 200, height: 50),
              paragraphs: [TextParagraph.plain('World')],
              autoFit: TextAutoFit.fixed,
            ),
            ShapeElement(
              id: 'c',
              frame: ElementFrame(x: 0, y: 200, width: 200, height: 50),
            ),
          ],
        ),
      ],
    );

/// Measures 40 slide units per paragraph.
double lines(TextBox box, SlideTheme? theme) => box.paragraphs.length * 40.0;

void main() {
  late SlideDocumentController doc;
  var next = 0;
  setUp(() {
    next = 0;
    doc = SlideDocumentController(
      deck(),
      newId: () => 'n${++next}',
      measureText: lines,
    );
  });

  TextBox box(String id) =>
      doc.presentation.slideById('s')!.elementById(id)! as TextBox;

  group('formatText', () {
    test('formats every selected text box whole, as one step', () {
      doc.formatText('s', {'a', 'b', 'c'}, const TextFormat(bold: true));
      expect(box('a').paragraphs.single.runs.single.bold, isTrue);
      expect(box('b').paragraphs.single.runs.single.bold, isTrue);
      doc.undo();
      expect(doc.presentation, deck());
      expect(doc.canUndo, isFalse);
    });

    test('sets box fields', () {
      doc.formatText(
        's',
        {'a'},
        const TextFormat(anchor: TextAnchor.bottom, autoFit: TextAutoFit.fixed),
      );
      expect(box('a').anchor, TextAnchor.bottom);
      expect(box('a').autoFit, TextAutoFit.fixed);
    });

    test('a format that changes nothing records no step', () {
      doc.formatText('s', {'a'}, const TextFormat(bold: false));
      expect(doc.canUndo, isFalse);
    });

    test('names a missing element', () {
      expect(
        () => doc.formatText('s', {'nope'}, const TextFormat(bold: true)),
        throwsArgumentError,
      );
    });
  });

  group('auto-grow', () {
    test('editText grows a growing box to its text in the same step', () {
      doc.editText('s', 'a', [
        TextParagraph.plain('1'),
        TextParagraph.plain('2'),
      ]);
      expect(box('a').frame.height, 80);
      doc.undo();
      expect(box('a').frame.height, 50);
    });

    test('it never shrinks a box', () {
      doc.editText('s', 'a', [TextParagraph.plain('')]);
      expect(box('a').frame.height, 50);
    });

    test('a fixed box keeps its size', () {
      doc.editText('s', 'b', List.filled(3, TextParagraph.plain('x')));
      expect(box('b').frame.height, 50);
    });

    test('resizing a growing box shorter than its text stops at the text', () {
      doc.editText('s', 'a', List.filled(3, TextParagraph.plain('x')));
      doc.resizeElement('s', 'a', width: 300, height: 10);
      expect(box('a').frame.width, 300);
      expect(box('a').frame.height, 120);
    });

    test('switching a box back to grow fits it at once', () {
      doc.editText('s', 'b', List.filled(3, TextParagraph.plain('x')));
      doc.formatText('s', {'b'}, const TextFormat(autoFit: TextAutoFit.grow));
      expect(box('b').frame.height, 120);
    });

    test('without a measurer nothing grows', () {
      doc = SlideDocumentController(deck());
      doc.editText('s', 'a', List.filled(3, TextParagraph.plain('x')));
      expect(box('a').frame.height, 50);
    });
  });

  group('insertTextBox', () {
    test('places an empty box one line tall in front, as one step', () {
      final id = doc.insertTextBox('s', at: (x: 300, y: 400));
      expect(id, 'n1');
      final inserted = box(id);
      expect(inserted.frame.x, 300);
      expect(inserted.frame.y, 400);
      expect(inserted.frame.width, SlideDocumentController.defaultTextBoxWidth);
      expect(inserted.frame.height, 40);
      expect(inserted.plainText, '');
      expect(doc.presentation.slideById('s')!.elements.last.id, id);
      doc.undo();
      expect(doc.presentation, deck());
    });

    test('takes a size, text, placeholder and stacking position', () {
      final id = doc.insertTextBox(
        's',
        at: (x: 0, y: 0),
        width: 100,
        height: 300,
        paragraphs: [TextParagraph.plain('Hi')],
        placeholder: 'Title',
        index: 0,
      );
      final inserted = box(id);
      expect(inserted.frame.width, 100);
      expect(inserted.frame.height, 300);
      expect(inserted.plainText, 'Hi');
      expect(inserted.placeholder, 'Title');
      expect(doc.presentation.slideById('s')!.elements.first.id, id);
    });

    test('without a measurer it uses the default height', () {
      doc = SlideDocumentController(deck(), newId: () => 'x');
      final id = doc.insertTextBox('s', at: (x: 0, y: 0));
      expect(
          box(id).frame.height, SlideDocumentController.defaultTextBoxHeight);
    });
  });

  test('SlideDocumentNotifier measures with SlideTextLayout by default', () {
    final notifier = SlideDocumentNotifier(deck());
    addTearDown(notifier.dispose);
    final controller = notifier.controller;
    controller.editText('s', 'a', List.filled(4, TextParagraph.plain('x')));
    final grown =
        notifier.presentation.slideById('s')!.elementById('a')!.frame.height;
    expect(grown, closeTo(4 * 36 * 1.2, 4));
  });
}
