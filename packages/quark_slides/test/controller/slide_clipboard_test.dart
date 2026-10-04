import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

ElementFrame f(double x, double y, double w, double h, [double r = 0]) =>
    ElementFrame(x: x, y: y, width: w, height: h, rotation: r);

/// Slide `s` holds a shape `a`, an image `pic` and a group `g` of shapes
/// `g1` and `g2`; slide `s2` is empty.
Presentation deck() => Presentation(
      slides: [
        Slide(
          id: 's',
          elements: [
            ShapeElement(
              id: 'a',
              frame: f(100, 100, 200, 100),
              fill: const SlideColor(0xFF3366FF),
            ),
            ImageElement(
              id: 'pic',
              frame: f(500, 100, 300, 200),
              source: 'asset:logo-1',
              altText: 'Logo',
            ),
            GroupElement(id: 'g', frame: f(1000, 500, 300, 300), children: [
              ShapeElement(id: 'g1', frame: f(0, 0, 100, 100)),
              ShapeElement(id: 'g2', frame: f(200, 200, 100, 100)),
            ]),
          ],
        ),
        const Slide(id: 's2'),
      ],
    );

/// A clipboard of its own, so tests do not share [SlideClipboard.memory].
SlideClipboard scratch() {
  String? text;
  return SlideClipboard(
    read: () async => text,
    write: (value) async => text = value,
  );
}

void main() {
  late SlideDocumentController doc;
  late SlideClipboard clipboard;
  setUp(() {
    doc = SlideDocumentController(deck());
    clipboard = scratch();
  });

  Slide slide([String id = 's']) => doc.presentation.slideById(id)!;

  int undoAll() {
    var steps = 0;
    while (doc.undo()) {
      steps++;
    }
    return steps;
  }

  group('SlideClipboardCodec', () {
    test('round-trips elements, groups and all', () {
      final elements = slide().elements;
      final text = SlideClipboardCodec.encode(elements);
      final json = jsonDecode(text) as Map;
      expect(json['format'], SlideClipboardCodec.format);
      expect(json['version'], SlideClipboardCodec.version);
      expect(SlideClipboardCodec.decode(text), elements);
    });

    test('other text is not a payload', () {
      expect(SlideClipboardCodec.decode('hello'), isNull);
      expect(SlideClipboardCodec.decode('{not json'), isNull);
      expect(SlideClipboardCodec.decode('{"a": 1}'), isNull);
    });

    test('a newer version is refused, an unknown element kept', () {
      expect(
        () => SlideClipboardCodec.decode(
            '{"format": "quark-slides/elements", "version": 2}'),
        throwsA(isA<QslideFormatException>()),
      );
      final kept = SlideClipboardCodec.decode(jsonEncode({
        'format': SlideClipboardCodec.format,
        'version': 1,
        'elements': [
          {
            'id': 'x',
            'type': 'chart',
            'frame': {'x': 0, 'y': 0, 'width': 10, 'height': 10},
            'series': [1, 2],
          },
        ],
      }))!;
      expect(kept.single, isA<UnknownElement>());
      expect(kept.single.toJson()['series'], [1, 2]);
    });
  });

  group('copy and paste', () {
    test('pasting back onto the same slide lands 16 past, then 32', () async {
      await clipboard.copy(doc, 's', {'a'});
      final first = await clipboard.paste(doc, 's');
      final second = await clipboard.paste(doc, 's');
      expect(slide().elementById(first.single)!.frame, f(116, 116, 200, 100));
      expect(slide().elementById(second.single)!.frame, f(132, 132, 200, 100));
      expect(first.single, isNot('a'));
      expect(undoAll(), 2);
    });

    test('pasting onto another slide keeps the place', () async {
      await clipboard.copy(doc, 's', {'a', 'pic'});
      final ids = await clipboard.paste(doc, 's2');
      expect(ids, hasLength(2));
      expect(slide('s2').elementById(ids.first)!.frame, f(100, 100, 200, 100));
      final image = slide('s2').elementById(ids.last) as ImageElement;
      expect(image.source, 'asset:logo-1');
      expect(image.altText, 'Logo');
    });

    test('a copied group pastes with fresh ids inside it too', () async {
      await clipboard.copy(doc, 's', {'g'});
      final ids = await clipboard.paste(doc, 's');
      final copy = slide().elementById(ids.single) as GroupElement;
      expect(copy.children.map((e) => e.id), isNot(contains('g1')));
      expect(copy.children.map((e) => e.id).toSet(), hasLength(2));
      expect(copy.frame, f(1016, 516, 300, 300));
      expect(copy.children.first.frame, f(0, 0, 100, 100));
    });

    test('a child copied out of its group pastes where it showed', () async {
      doc.rotateElement('s', 'g', 90);
      final shown = slide().frameOnSlide('g2')!;
      await clipboard.copy(doc, 's', {'g2'});
      final ids = await clipboard.paste(doc, 's2');
      final pasted = slide('s2').elementById(ids.single)!.frame;
      expect(pasted.x, closeTo(shown.x, 1e-6));
      expect(pasted.rotation, closeTo(90, 1e-6));
    });

    test('pastes across presentations through the shared clipboard', () async {
      await clipboard.copy(doc, 's', {'a'});
      final other = SlideDocumentController(
        Presentation(slides: [const Slide(id: 'x')]),
      );
      final ids = await clipboard.paste(other, 'x');
      expect(other.presentation.slideById('x')!.elementById(ids.single),
          isA<ShapeElement>());
    });

    test('the in-app memory clipboard is shared', () async {
      await SlideClipboard.memory.copy(doc, 's', {'a'});
      final ids = await SlideClipboard.memory.paste(doc, 's2');
      expect(ids, hasLength(1));
    });

    test('cut copies then deletes as one step', () async {
      await clipboard.cut(doc, 's', {'a', 'pic'});
      expect(slide().elements.map((e) => e.id), ['g']);
      expect(undoAll(), 1);
      expect(slide().elements, hasLength(3));
      final ids = await clipboard.paste(doc, 's');
      expect(ids, hasLength(2));
    });

    test('plain text pastes as a centered text box, a paragraph a line',
        () async {
      await clipboard.write('Hello\r\nworld');
      final ids = await clipboard.paste(doc, 's');
      final box = slide().elementById(ids.single) as TextBox;
      expect(box.plainText, 'Hello\nworld');
      expect(box.frame.x, (1920 - 600) / 2);
      expect(undoAll(), 1);
    });

    test('blank, empty or newer clipboards paste nothing', () async {
      expect(await clipboard.paste(doc, 's'), isEmpty);
      await clipboard.write('   \n');
      expect(await clipboard.paste(doc, 's'), isEmpty);
      await clipboard
          .write('{"format": "quark-slides/elements", "version": 9}');
      expect(await clipboard.paste(doc, 's'), isEmpty);
      expect(doc.canUndo, isFalse);
    });

    test('copying nothing leaves the clipboard alone', () async {
      await clipboard.write('kept');
      await clipboard.copy(doc, 's', const []);
      expect(await clipboard.read(), 'kept');
    });
  });

  group('duplicateElements', () {
    test('duplicates in place, 16 past each time, one step each', () {
      final first = doc.duplicateElements('s', {'a', 'pic'});
      final second = doc.duplicateElements('s', {'a'});
      expect(slide().elementById(first.first)!.frame, f(116, 116, 200, 100));
      expect(slide().elementById(first.last)!.frame.x, 516);
      expect(slide().elementById(second.single)!.frame,
          f(116, 116, 200, 100).translate(16, 16));
      expect(slide().elements.map((e) => e.id).skip(3), [...first, ...second]);
      expect(undoAll(), 2);
    });

    test('an element and its group copy once, with the group', () {
      expect(doc.copyElements('s', {'g', 'g1'}).map((e) => e.id), ['g']);
    });
  });
}
