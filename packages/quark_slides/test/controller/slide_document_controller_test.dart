import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/sample_presentation.dart';

/// A controller over the sample deck with predictable ids `n1`, `n2`, ...
/// and a count of its change notifications.
class Harness {
  Harness([Presentation? presentation, int maxUndoDepth = 100]) {
    doc = SlideDocumentController(
      presentation ?? samplePresentation(),
      newId: () => 'n${++_next}',
      onChanged: () => changes++,
      maxUndoDepth: maxUndoDepth,
    );
  }

  late final SlideDocumentController doc;
  int changes = 0;
  int _next = 0;

  List<String> get slideIds => [for (final s in doc.presentation.slides) s.id];

  List<String> elementIds(String slideId) => [
        for (final e in doc.presentation.slideById(slideId)!.elements) e.id,
      ];

  ElementFrame frameOf(String slideId, String elementId) =>
      doc.presentation.slideById(slideId)!.elementById(elementId)!.frame;
}

void main() {
  group('slides', () {
    test('addSlide appends a blank slide and returns its id', () {
      final h = Harness();
      final id = h.doc.addSlide();
      expect(id, 'n1');
      expect(h.slideIds, ['s1', 's2', 's3', 'n1']);
      expect(h.doc.presentation.slides.last.elements, isEmpty);
      expect(h.changes, 1);
    });

    test('addSlide inserts at an index', () {
      final h = Harness();
      h.doc.addSlide(index: 0);
      expect(h.slideIds, ['n1', 's1', 's2', 's3']);
      expect(() => h.doc.addSlide(index: 9), throwsRangeError);
    });

    test('duplicateSlide inserts a copy after the source with fresh ids', () {
      final h = Harness();
      final copyId = h.doc.duplicateSlide('s2');
      expect(h.slideIds, ['s1', 's2', 'n1', 's3']);
      expect(h.elementIds(copyId), ['n2', 'n3', 'n4']);
      final source = h.doc.presentation.slideById('s2')!;
      final copy = h.doc.presentation.slideById(copyId)!;
      expect(copy.background, source.background);
      for (var i = 0; i < source.elements.length; i++) {
        expect(
            copy.elements[i].withId(source.elements[i].id), source.elements[i]);
      }
    });

    test('generated ids skip ones already in use', () {
      final ids = ['s1', 'e1', 'fresh'];
      final doc = SlideDocumentController(
        samplePresentation(),
        newId: () => ids.removeAt(0),
      );
      expect(doc.newId(), 'fresh');
    });

    test('the default id generator gives distinct ids', () {
      final doc = SlideDocumentController(Presentation());
      final ids = {for (var i = 0; i < 50; i++) doc.addSlide()};
      expect(ids, hasLength(50));
    });

    test('deleteSlide removes it', () {
      final h = Harness();
      h.doc.deleteSlide('s2');
      expect(h.slideIds, ['s1', 's3']);
    });

    test('moveSlide puts the slide at the target index', () {
      final h = Harness();
      h.doc.moveSlide('s1', 2);
      expect(h.slideIds, ['s2', 's3', 's1']);
      h.doc.moveSlide('s1', 0);
      expect(h.slideIds, ['s1', 's2', 's3']);
      expect(() => h.doc.moveSlide('s1', 3), throwsRangeError);
    });

    test('setSlideNotes replaces the notes', () {
      final h = Harness();
      h.doc.setSlideNotes('s3', 'Questions?');
      expect(h.doc.presentation.slideById('s3')!.notes, 'Questions?');
    });

    test('an unknown slide id throws', () {
      final h = Harness();
      expect(() => h.doc.deleteSlide('nope'), throwsArgumentError);
      expect(() => h.doc.duplicateSlide('nope'), throwsArgumentError);
      expect(h.changes, 0);
    });
  });

  group('elements', () {
    test('addElement puts it in front by default, or at an index', () {
      final h = Harness();
      final frame = ElementFrame(x: 0, y: 0, width: 10, height: 10);
      h.doc.addElement('s3', ShapeElement(id: h.doc.newId(), frame: frame));
      h.doc.addElement(
        's3',
        TextBox(id: h.doc.newId(), frame: frame),
        index: 0,
      );
      expect(h.elementIds('s3'), ['n2', 'n1']);
    });

    test('addElement refuses an id already in use', () {
      final h = Harness();
      final frame = ElementFrame(x: 0, y: 0, width: 1, height: 1);
      for (final id in ['e1', 's1']) {
        expect(
          () => h.doc.addElement('s3', ShapeElement(id: id, frame: frame)),
          throwsArgumentError,
          reason: id,
        );
      }
    });

    test('moveElements moves every listed element, and only those', () {
      final h = Harness();
      h.doc.moveElements('s2', ['e3', 'e5'], 10, -5);
      expect(h.frameOf('s2', 'e3').x, 10);
      expect(h.frameOf('s2', 'e3').y, -5);
      expect(h.frameOf('s2', 'e5').x, 1210);
      expect(h.frameOf('s2', 'e4').x, 1000);
      h.doc.undo();
      expect(h.frameOf('s2', 'e3').x, 0);
      expect(h.frameOf('s2', 'e5').x, 1200);
    });

    test('moveElements with an unknown id changes nothing', () {
      final h = Harness();
      expect(
        () => h.doc.moveElements('s2', ['e3', 'nope'], 1, 1),
        throwsArgumentError,
      );
      expect(h.frameOf('s2', 'e3').x, 0);
      expect(h.doc.canUndo, isFalse);
    });

    test('resizeElement keeps the corner unless told to move it', () {
      final h = Harness();
      h.doc.resizeElement('s2', 'e5', width: 50, height: 60);
      expect(h.frameOf('s2', 'e5'),
          ElementFrame(x: 1200, y: 700, width: 50, height: 60));
      h.doc.resizeElement('s2', 'e5', x: 1100, width: 150, height: 60);
      expect(h.frameOf('s2', 'e5'),
          ElementFrame(x: 1100, y: 700, width: 150, height: 60));
      expect(
        () => h.doc.resizeElement('s2', 'e5', width: -1, height: 1),
        throwsArgumentError,
      );
    });

    test('rotateElement sets the rotation and keeps the box', () {
      final h = Harness();
      h.doc.rotateElement('s1', 'e2', 90);
      expect(h.frameOf('s1', 'e2').rotation, 90);
      expect(h.frameOf('s1', 'e2').width, 400);
    });

    test('deleteElements removes every listed element', () {
      final h = Harness();
      h.doc.deleteElements('s2', ['e3', 'e5']);
      expect(h.elementIds('s2'), ['e4']);
    });

    test('reorderElement changes the stacking order', () {
      final h = Harness();
      h.doc.reorderElement('s2', 'e5', 0);
      expect(h.elementIds('s2'), ['e5', 'e3', 'e4']);
      h.doc.reorderElement('s2', 'e5', 2);
      expect(h.elementIds('s2'), ['e3', 'e4', 'e5']);
      expect(() => h.doc.reorderElement('s2', 'e5', 3), throwsRangeError);
    });

    test('editText replaces a text box\'s paragraphs', () {
      final h = Harness();
      h.doc.editText('s1', 'e1', [
        TextParagraph.plain('New title'),
        const TextParagraph([TextRun('bold', bold: true)]),
      ]);
      final box = h.doc.presentation.slideById('s1')!.elementById('e1')!;
      expect((box as TextBox).plainText, 'New title\nbold');
      expect(box.frame, ElementFrame(x: 160, y: 120, width: 1600, height: 240));
    });

    test('editText refuses an element that is not a text box', () {
      final h = Harness();
      expect(() => h.doc.editText('s1', 'e2', const []), throwsArgumentError);
    });

    test('an element id on a different slide throws', () {
      final h = Harness();
      expect(() => h.doc.rotateElement('s2', 'e1', 1), throwsArgumentError);
    });

    test('an unknown element moves like any other', () {
      final h = Harness(Presentation());
      final slide = h.doc.addSlide();
      h.doc.addElement(
        slide,
        UnknownElement(
          id: 'c',
          frame: ElementFrame(x: 0, y: 0, width: 1, height: 1),
          extra: const {'type': 'chart', 'series': []},
        ),
      );
      h.doc.moveElements(slide, ['c'], 3, 4);
      final chart = h.doc.presentation.slideById(slide)!.elementById('c')!;
      expect(chart.frame.x, 3);
      expect(chart.toJson()['type'], 'chart');
      expect(chart.toJson()['series'], isEmpty);
    });
  });

  group('undo and redo', () {
    test('undo reverts and redo reapplies each step in order', () {
      final h = Harness();
      final original = h.doc.presentation;
      h.doc.addSlide();
      final afterAdd = h.doc.presentation;
      h.doc.deleteSlide('s1');
      expect(h.doc.undo(), isTrue);
      expect(h.doc.presentation, afterAdd);
      expect(h.doc.undo(), isTrue);
      expect(h.doc.presentation, original);
      expect(h.doc.undo(), isFalse);
      expect(h.doc.redo(), isTrue);
      expect(h.doc.redo(), isTrue);
      expect(h.slideIds, ['s2', 's3', 'n1']);
      expect(h.doc.redo(), isFalse);
    });

    test('a new command clears the redo stack', () {
      final h = Harness();
      h.doc.addSlide();
      h.doc.undo();
      expect(h.doc.canRedo, isTrue);
      h.doc.setSlideNotes('s1', 'x');
      expect(h.doc.canRedo, isFalse);
    });

    test('undo and redo notify', () {
      final h = Harness();
      h.doc.addSlide();
      h.doc.undo();
      h.doc.redo();
      h.doc.undo();
      h.doc.undo(); // nothing left: no notification
      expect(h.changes, 4);
    });

    test('a command that changes nothing records no step', () {
      final h = Harness();
      h.doc.moveElements('s2', ['e3'], 0, 0);
      h.doc.reorderElement('s2', 'e3', 0);
      h.doc.moveSlide('s2', 1);
      h.doc.setSlideNotes('s1', 'Welcome everyone.');
      expect(h.doc.canUndo, isFalse);
      expect(h.changes, 0);
    });

    test('history keeps the newest 100 steps', () {
      final h = Harness();
      final original = h.doc.presentation;
      for (var i = 0; i < 101; i++) {
        h.doc.moveElements('s2', ['e3'], 1, 0);
      }
      var undone = 0;
      while (h.doc.undo()) {
        undone++;
      }
      expect(undone, 100);
      expect(h.frameOf('s2', 'e3').x, 1);
      expect(h.doc.presentation, isNot(original));
    });

    test('the depth limit is configurable', () {
      final h = Harness(null, 2);
      for (var i = 0; i < 5; i++) {
        h.doc.addSlide();
      }
      expect(h.doc.undo() && h.doc.undo(), isTrue);
      expect(h.doc.undo(), isFalse);
    });

    test('load replaces the presentation and clears history', () {
      final h = Harness();
      h.doc.addSlide();
      h.doc.undo();
      h.doc.load(Presentation(title: 'Other'));
      expect(h.doc.presentation.title, 'Other');
      expect(h.doc.canUndo, isFalse);
      expect(h.doc.canRedo, isFalse);
    });
  });

  group('batches', () {
    test('a batch of commands undoes as one step', () {
      final h = Harness();
      final original = h.doc.presentation;
      h.doc.batch(() {
        h.doc.moveElements('s2', ['e3'], 5, 0);
        h.doc.moveElements('s2', ['e3'], 5, 0);
        h.doc.addSlide();
      });
      expect(h.frameOf('s2', 'e3').x, 10);
      h.doc.undo();
      expect(h.doc.presentation, original);
      expect(h.doc.canUndo, isFalse);
      h.doc.redo();
      expect(h.frameOf('s2', 'e3').x, 10);
      expect(h.slideIds, hasLength(4));
    });

    test('commands inside a batch apply and notify at once', () {
      final h = Harness();
      h.doc.beginBatch();
      h.doc.moveElements('s2', ['e3'], 5, 0);
      expect(h.frameOf('s2', 'e3').x, 5);
      expect(h.changes, 1);
      expect(h.doc.canUndo, isFalse);
      h.doc.endBatch();
      expect(h.doc.canUndo, isTrue);
    });

    test('nested batches record one step when the outermost ends', () {
      final h = Harness();
      h.doc.batch(() {
        h.doc.addSlide();
        h.doc.batch(() => h.doc.addSlide());
        expect(h.doc.canUndo, isFalse);
        h.doc.addSlide();
      });
      h.doc.undo();
      expect(h.slideIds, ['s1', 's2', 's3']);
    });

    test('a batch that changes nothing records no step', () {
      final h = Harness();
      h.doc.batch(() {
        h.doc.moveElements('s2', ['e3'], 5, 0);
        h.doc.moveElements('s2', ['e3'], -5, 0);
      });
      expect(h.doc.canUndo, isFalse);
    });

    test('batch returns the body\'s result and closes on a throw', () {
      final h = Harness();
      expect(h.doc.batch(h.doc.addSlide), 'n1');
      expect(
        () => h.doc.batch(() {
          h.doc.addSlide();
          h.doc.deleteSlide('nope');
        }),
        throwsArgumentError,
      );
      expect(h.doc.isBatching, isFalse);
      h.doc.undo();
      expect(h.slideIds, ['s1', 's2', 's3', 'n1']);
    });

    test('undo, redo and load are refused inside a batch', () {
      final h = Harness();
      h.doc.addSlide();
      h.doc.beginBatch();
      expect(h.doc.undo, throwsStateError);
      expect(h.doc.redo, throwsStateError);
      expect(() => h.doc.load(Presentation()), throwsStateError);
      h.doc.endBatch();
    });

    test('endBatch without beginBatch throws', () {
      expect(Harness().doc.endBatch, throwsStateError);
    });
  });
}
