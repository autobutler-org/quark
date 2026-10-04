import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

ElementFrame f(double x, double y, double w, double h, [double r = 0]) =>
    ElementFrame(x: x, y: y, width: w, height: h, rotation: r);

/// A 1920×1080 deck with slide `s` holding shapes `a`, `b` and `c` and a
/// text box `t`, back to front, and an empty slide `s2`.
Presentation deck() => Presentation(
      slides: [
        Slide(
          id: 's',
          elements: [
            ShapeElement(id: 'a', frame: f(100, 100, 200, 100)),
            ShapeElement(id: 'b', frame: f(400, 300, 100, 100)),
            ShapeElement(id: 'c', frame: f(1000, 600, 300, 200)),
            TextBox(
              id: 't',
              frame: f(800, 100, 200, 50),
              paragraphs: const [
                TextParagraph([TextRun('Hi')]),
              ],
            ),
          ],
        ),
        const Slide(id: 's2'),
      ],
    );

Matcher frameNear(ElementFrame expected) => isA<ElementFrame>()
    .having((e) => e.x, 'x', closeTo(expected.x, 1e-6))
    .having((e) => e.y, 'y', closeTo(expected.y, 1e-6))
    .having((e) => e.width, 'width', closeTo(expected.width, 1e-6))
    .having((e) => e.height, 'height', closeTo(expected.height, 1e-6))
    .having((e) => e.rotation % 360, 'rotation',
        closeTo(expected.rotation % 360, 1e-6));

void main() {
  late SlideDocumentController doc;
  var next = 0;
  setUp(() {
    next = 0;
    doc = SlideDocumentController(deck(), newId: () => 'n${next++}');
  });

  Slide slide() => doc.presentation.slideById('s')!;
  List<String> topIds() => [for (final e in slide().elements) e.id];

  int undoAll() {
    var steps = 0;
    while (doc.undo()) {
      steps++;
    }
    return steps;
  }

  group('groupElements', () {
    test('groups as one step, in place of the frontmost member', () {
      final before = doc.presentation;
      final id = doc.groupElements('s', {'b', 'a'});
      expect(topIds(), [id, 'c', 't']);
      final group = slide().elementById(id) as GroupElement;
      expect(group.children.map((e) => e.id), ['a', 'b']);
      expect(group.frame, f(100, 100, 400, 300));
      // Nothing moved on the slide.
      expect(slide().frameOnSlide('b'), f(400, 300, 100, 100));
      expect(undoAll(), 1);
      expect(doc.presentation, before);
    });

    test('the group takes the frontmost member’s place in the stack', () {
      final id = doc.groupElements('s', {'a', 'c'});
      expect(topIds(), ['b', id, 't']);
    });

    test('canGroup wants two or more sharing a parent', () {
      expect(doc.canGroup('s', {'a'}), isFalse);
      expect(doc.canGroup('s', {'a', 'b'}), isTrue);
      expect(doc.canGroup('s', {'a', 'nope'}), isFalse);
      doc.groupElements('s', {'a', 'b'});
      expect(doc.canGroup('s', {'a', 'c'}), isFalse);
      expect(() => doc.groupElements('s', {'a', 'c'}), throwsArgumentError);
      expect(() => doc.groupElements('s', {'a'}), throwsArgumentError);
    });

    test('elements inside a group group into a nested group', () {
      final outer = doc.groupElements('s', {'a', 'b', 'c'});
      final inner = doc.groupElements('s', {'a', 'b'});
      final group = slide().elementById(outer) as GroupElement;
      expect(group.children.map((e) => e.id), [inner, 'c']);
      expect(slide().ancestorsOf('a')!.map((g) => g.id), [outer, inner]);
      expect(slide().frameOnSlide('b'), frameNear(f(400, 300, 100, 100)));
    });
  });

  group('ungroupElements', () {
    test('frees the children in the group’s place, as one step', () {
      final id = doc.groupElements('s', {'a', 'b'});
      doc.rotateElement('s', id, 90);
      final shown = slide().frameOnSlide('a')!;
      final freed = doc.ungroupElements('s', {id, 't'});
      expect(freed, ['a', 'b']);
      expect(topIds(), ['a', 'b', 'c', 't']);
      expect(slide().elementById('a')!.frame, frameNear(shown));
      expect(slide().elementById('a')!.frame.rotation, closeTo(90, 1e-9));
      doc.undo();
      expect(slide().elementById(id), isA<GroupElement>());
    });

    test('a nested group stays a group', () {
      final inner = doc.groupElements('s', {'a', 'b'});
      final outer = doc.groupElements('s', {inner, 'c'});
      expect(doc.ungroupElements('s', {outer}), [inner, 'c']);
      expect(slide().elementById(inner), isA<GroupElement>());
    });

    test('canUngroup wants a group; nothing else changes anything', () {
      expect(doc.canUngroup('s', {'a'}), isFalse);
      expect(doc.ungroupElements('s', {'a'}), isEmpty);
      expect(doc.canUndo, isFalse);
      final id = doc.groupElements('s', {'a', 'b'});
      expect(doc.canUngroup('s', {id}), isTrue);
    });
  });

  group('a group as a unit', () {
    late String id;
    setUp(() => id = doc.groupElements('s', {'a', 'b'}));

    test('moves without touching its children’s local frames', () {
      final children = (slide().elementById(id) as GroupElement).children;
      doc.moveElements('s', {id}, 50, 10);
      final group = slide().elementById(id) as GroupElement;
      expect(group.frame, f(150, 110, 400, 300));
      expect(group.children, children);
      expect(slide().frameOnSlide('a'), f(150, 110, 200, 100));
    });

    test('resizes scaling its children', () {
      doc.resizeElement('s', id, width: 800, height: 150);
      expect(slide().frameOnSlide('a'), frameNear(f(100, 100, 400, 50)));
      expect(slide().frameOnSlide('b'), frameNear(f(700, 200, 200, 50)));
    });

    test('rotates about its center, taking its children with it', () {
      doc.rotateElement('s', id, 180);
      // Turned half way, the top-left child lands bottom-right.
      expect(slide().frameOnSlide('a'), frameNear(f(300, 300, 200, 100, 180)));
    });

    test('duplicating the slide renews every id, inside groups too', () {
      final copy = doc.duplicateSlide('s');
      final ids = [
        for (final e in doc.presentation.slideById(copy)!.allElements) e.id,
      ];
      expect(ids, hasLength(5));
      expect(
          ids.toSet().intersection(
            {for (final e in slide().allElements) e.id},
          ),
          isEmpty);
    });

    test('newId skips ids taken inside groups', () {
      var calls = 0;
      final d = SlideDocumentController(doc.presentation, newId: () {
        calls++;
        return calls == 1 ? 'a' : 'fresh';
      });
      expect(d.newId(), 'fresh');
    });
  });

  group('editing inside a group', () {
    late String id;
    setUp(() {
      id = doc.groupElements('s', {'a', 'b'});
      doc.rotateElement('s', id, 90);
    });

    test('moving a child moves it along the slide and refits the group', () {
      final before = slide().frameOnSlide('b')!;
      final other = slide().frameOnSlide('a')!;
      doc.moveElements('s', {'b'}, 100, 0);
      expect(slide().frameOnSlide('b'), frameNear(before.translate(100, 0)));
      expect(slide().frameOnSlide('a'), frameNear(other));
      final group = slide().elementById(id)!;
      final box = frameBox(group.frame);
      // Turned a quarter, `b` is the leftmost child: the group follows it.
      final childBox = frameBox(slide().frameOnSlide('b')!);
      expect(box.left, closeTo(childBox.left, 1e-6));
      expect(box.left, closeTo(250, 1e-6));
    });

    test('resize and rotate take frames on the slide', () {
      final shown = slide().frameOnSlide('a')!;
      doc.resizeElement('s', 'a',
          x: shown.x, y: shown.y, width: 300, height: shown.height);
      expect(slide().frameOnSlide('a')!.width, closeTo(300, 1e-6));
      doc.rotateElement('s', 'a', 135);
      expect(slide().frameOnSlide('a')!.rotation, closeTo(135, 1e-6));
    });

    test('style, delete and stacking reach the child', () {
      doc.styleElements('s', {'a'}, const ElementStyle(opacity: 0.5));
      expect((slide().findElement('a') as ShapeElement).opacity, 0.5);
      doc.arrangeElements('s', {'a'}, ZOrderMove.toFront);
      expect((slide().elementById(id) as GroupElement).children.last.id, 'a');
    });

    test('deleting down to one child dissolves the group in place', () {
      final shown = slide().frameOnSlide('a')!;
      doc.deleteElements('s', {'b'});
      expect(topIds(), ['a', 'c', 't']);
      expect(slide().elementById('a')!.frame, frameNear(shown));
    });

    test('an unknown id is refused', () {
      expect(() => doc.moveElements('s', {'zz'}, 1, 1), throwsArgumentError);
    });
  });

  group('alignment commands', () {
    test('align, one step, moving only', () {
      doc.alignElements('s', {'a', 'b', 'c'}, ElementAlignment.top);
      expect([for (final id in 'abc'.split('')) slide().frameOnSlide(id)!.y],
          [100, 100, 100]);
      expect(slide().elementById('c')!.frame.width, 300);
      expect(undoAll(), 1);
    });

    test('a single element aligns to the slide', () {
      doc.alignElements('s', {'b'}, ElementAlignment.center);
      expect(slide().elementById('b')!.frame.x, 910);
      doc.alignElements('s', {'b'}, ElementAlignment.bottom);
      expect(slide().elementById('b')!.frame.y, 980);
    });

    test('several align to the slide when asked', () {
      doc.alignElements('s', {'a', 'b'}, ElementAlignment.left, toSlide: true);
      expect(slide().elementById('a')!.frame.x, 0);
      expect(slide().elementById('b')!.frame.x, 0);
    });

    test('distribute, one step', () {
      doc.distributeElements('s', {'a', 'b', 'c'}, DistributeAxis.horizontal);
      // Spans 100–1300 with 600 wide of shapes: gaps of 300.
      expect(slide().elementById('b')!.frame.x, 600);
      expect(undoAll(), 1);
    });

    test('match size, one step; a group scales its children', () {
      final id = doc.groupElements('s', {'a', 'b'});
      doc.matchSize('s', {id, 'c'}, SizeMatch.width, reference: 'c');
      expect(slide().elementById(id)!.frame.width, closeTo(300, 1e-6));
      expect(slide().frameOnSlide('a')!.width, closeTo(150, 1e-6));
      doc.undo();
      expect(slide().elementById(id)!.frame.width, 400);
    });

    test('aligns grouped elements by where they show', () {
      doc.groupElements('s', {'a', 'b'});
      doc.alignElements('s', {'a', 'b'}, ElementAlignment.right);
      expect(slide().frameOnSlide('a')!.x + 200, closeTo(500, 1e-6));
    });

    test('a text box that grows refits after a match', () {
      final grow = SlideDocumentController(
        deck(),
        measureText: (box) => 400,
      );
      grow.matchSize('s', {'t', 'b'}, SizeMatch.width, reference: 'b');
      expect(grow.presentation.slideById('s')!.elementById('t')!.frame.height,
          400);
    });
  });
}
