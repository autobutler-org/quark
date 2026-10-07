import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/find/slide_find_controller.dart';
import 'package:quark_slides/quark_slides.dart';

ElementFrame frame() => ElementFrame(x: 0, y: 0, width: 400, height: 100);

/// Three slides: `a` (`cat`), `b` (`cat cat`, notes `cat`), `c` (`dog`).
Presentation deck() => Presentation(
  slides: [
    Slide(
      id: 'a',
      elements: [
        TextBox(
          id: 'ta',
          frame: frame(),
          paragraphs: [TextParagraph.plain('cat')],
        ),
      ],
    ),
    Slide(
      id: 'b',
      notes: 'cat',
      elements: [
        TextBox(
          id: 'tb',
          frame: frame(),
          paragraphs: [TextParagraph.plain('cat cat')],
        ),
      ],
    ),
    Slide(
      id: 'c',
      elements: [
        TextBox(
          id: 'tc',
          frame: frame(),
          paragraphs: [TextParagraph.plain('dog')],
        ),
      ],
    ),
  ],
);

/// The find controller over a document and a "canvas" showing [slide].
class Harness {
  Harness({String slide = 'a'}) : slide = ValueNotifier(slide) {
    find = SlideFindController(
      source: Listenable.merge([doc, this.slide]),
      document: () => doc,
      currentSlideId: () => this.slide.value,
      showSlide: (id) {
        shown.add(id);
        this.slide.value = id;
      },
    );
  }

  final doc = SlideDocumentNotifier(deck());
  final ValueNotifier<String> slide;
  final shown = <String>[];
  late final SlideFindController find;

  String? get at => find.current == null
      ? null
      : '${find.current!.slideId}:${find.current!.field.name}:'
            '${find.current!.start}';

  void dispose() {
    find.dispose();
    doc.dispose();
    slide.dispose();
  }
}

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  test('starts closed, with nothing to highlight', () {
    expect(h.find.isOpen, isFalse);
    h.find.query.text = 'cat';
    expect(h.find.highlights, isEmpty);
    expect(h.find.current, isNull);
  });

  test('typing searches and lands on the first match from the canvas', () {
    h.slide.value = 'b';
    h.find.open();
    h.find.query.text = 'cat';
    expect(h.find.result.length, 3);
    expect(h.at, 'b:text:0');
    expect(h.find.status, '2 of 3');
    expect(h.find.highlights, h.find.result.matches);
  });

  test('next and previous wrap and move the canvas', () {
    h.find.open();
    h.find.query.text = 'cat';
    expect(h.at, 'a:text:0');
    h.find.next();
    expect(h.at, 'b:text:0');
    expect(h.shown, ['b']);
    h.find.next();
    h.find.next();
    expect(h.at, 'a:text:0', reason: 'wrapped');
    h.find.previous();
    expect(h.at, 'b:text:4');
    expect(h.find.status, '3 of 3');
  });

  test('moving the caret does not search again', () {
    h.find.open();
    h.find.query.text = 'cat';
    h.find.next();
    h.find.query.selection = const TextSelection.collapsed(offset: 1);
    expect(h.at, 'b:text:0');
  });

  test('options search again and keep the place', () {
    h.find.open();
    h.find.query.text = 'cat';
    h.find.next();
    h.find.toggleNotes();
    expect(h.find.result.length, 4);
    expect(h.at, 'b:text:0');
    h.find.toggleCurrentSlide();
    expect(h.find.scope, SlideFindScope.currentSlide);
    expect(h.find.result.length, 3, reason: 'slide b, notes included');
    h.find.toggleWholeWord();
    h.find.toggleCaseSensitive();
    h.find.toggleRegex();
    expect(
      (h.find.wholeWord, h.find.caseSensitive, h.find.regex),
      (true, true, true),
    );
  });

  test('the slide scope follows the canvas', () {
    h.find.open();
    h.find.toggleCurrentSlide();
    h.find.query.text = 'cat';
    expect(h.find.result.length, 1);
    h.slide.value = 'b';
    expect(h.find.result.length, 2);
  });

  test('a bad pattern says so', () {
    h.find.open();
    h.find.toggleRegex();
    h.find.query.text = '(';
    expect(h.find.status, 'Invalid pattern');
    h.find.query.text = '(a+)+';
    expect(h.find.status, 'Pattern too complex');
    h.find.query.text = 'zebra';
    expect(h.find.status, 'No results');
    h.find.query.text = '';
    expect(h.find.status, '');
  });

  test('replace replaces the current match and moves past it', () {
    h.find.open();
    h.find.query.text = 'cat';
    h.find.next(); // b, first cat
    h.find.replacement.text = 'concat';
    h.find.replaceCurrent();
    final tb = h.doc.presentation.slides[1].findElement('tb')! as TextBox;
    expect(tb.plainText, 'concat cat');
    expect(h.at, 'b:text:7', reason: 'past the replacement, not into it');
    expect(h.doc.controller.canUndo, isTrue);
    h.doc.controller.undo();
    expect(h.doc.presentation, deck());
  });

  test('replace all is one undo step and leaves no match', () {
    h.find.open();
    h.find.toggleNotes();
    h.find.query.text = 'cat';
    h.find.replacement.text = 'dog';
    expect(h.find.replaceAll(), 4);
    expect(h.find.result.isEmpty, isTrue);
    expect(h.find.status, 'No results');
    h.doc.controller.undo();
    expect(h.doc.presentation, deck());
    expect(h.find.result.length, 4, reason: 'undo found them again');
  });

  test('an edit elsewhere searches again and keeps the place', () {
    h.find.open();
    h.find.query.text = 'cat';
    h.find.next();
    h.doc.controller.editText('a', 'ta', [TextParagraph.plain('cat cat')]);
    expect(h.find.result.length, 4);
    expect(h.at, 'b:text:0');
  });

  test('close hides the highlights; toggle opens and closes', () {
    h.find.open(replace: true);
    expect(h.find.showReplace, isTrue);
    h.find.query.text = 'cat';
    h.find.toggle();
    expect(h.find.isOpen, isFalse);
    expect(h.find.highlights, isEmpty);
    h.find.toggle();
    expect(h.find.isOpen, isTrue);
    expect(h.find.highlights, hasLength(3));
  });

  test('open selects the query so typing replaces it', () {
    h.find.open();
    h.find.query.text = 'cat';
    h.find.close();
    h.find.open();
    expect(
      h.find.query.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
  });
}
