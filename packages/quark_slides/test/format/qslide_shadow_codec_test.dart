import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

Matcher throwsFormatAt(String path) =>
    throwsA(isA<QslideFormatException>().having((e) => e.path, 'path', path));

/// A one-slide deck at [version] holding [element].
Map<String, Object?> deckWith(
  Map<String, Object?> element, {
  int version = 6,
}) => {
  'schemaVersion': version,
  'slides': [
    {
      'id': 's',
      'elements': [element],
    },
  ],
};

const _frame = {'x': 10, 'y': 20, 'width': 30, 'height': 40};

void main() {
  final frame = ElementFrame(x: 10, y: 20, width: 30, height: 40);
  final shadow = ElementShadow(
    color: const SlideColor(0x7F000000),
    x: -4.24,
    y: 4.24,
    blur: 61,
  );

  SlideElement only(Presentation deck) => deck.slides.single.elements.single;

  group('a shape shadow', () {
    test('round-trips through .qslide', () {
      final shape = ShapeElement(
        id: 'e',
        frame: frame,
        fill: SlideColor.white,
        shadow: shadow,
      );
      final saved = QslideCodec.encode(
        Presentation(
          slides: [
            Slide(id: 's', elements: [shape]),
          ],
        ),
      );
      expect(saved, contains('"schemaVersion": 6'));
      final json =
          (jsonDecode(saved)['slides'] as List).single['elements'].single
              as Map;
      expect(json['shadow'], {
        'color': '#0000007F',
        'x': -4.24,
        'y': 4.24,
        'blur': 61,
      });
      expect(only(QslideCodec.decode(saved)), shape);
    });

    test('leaves a zero offset and blur out', () {
      expect(ElementShadow(color: SlideColor.black).toJson(), {
        'color': '#000000',
      });
    });

    test('reads with defaults, and a negative blur as 0', () {
      final read =
          only(
                QslideCodec.fromJson(
                  deckWith({
                    'id': 'e',
                    'type': 'shape',
                    'kind': 'rectangle',
                    'frame': _frame,
                    'shadow': {'blur': -3},
                  }),
                ),
              )
              as ShapeElement;
      expect(read.shadow, ElementShadow(color: SlideColor.black));
    });

    test('keeps fields a newer writer added to it', () {
      final read =
          only(
                QslideCodec.fromJson(
                  deckWith({
                    'id': 'e',
                    'type': 'shape',
                    'kind': 'rectangle',
                    'frame': _frame,
                    'shadow': {'color': '#FF0000', 'spread': 2},
                  }),
                ),
              )
              as ShapeElement;
      expect(read.shadow!.color, const SlideColor(0xFFFF0000));
      expect(read.toJson()['shadow'], {'color': '#FF0000', 'spread': 2});
    });

    test('a mistyped shadow is refused at its path', () {
      expect(
        () => QslideCodec.fromJson(
          deckWith({
            'id': 'e',
            'type': 'shape',
            'kind': 'rectangle',
            'frame': _frame,
            'shadow': {'x': 'far'},
          }),
        ),
        throwsFormatAt(r'$.slides[0].elements[0].shadow.x'),
      );
    });

    test('copyWith keeps, replaces and clears it', () {
      final shape = ShapeElement(id: 'e', frame: frame, shadow: shadow);
      expect(shape.copyWith(opacity: 0.5).shadow, shadow);
      expect(shape.copyWith(kind: ShapeKind.star).shadow, shadow);
      expect(shape.copyWith(shadow: null).shadow, isNull);
      final other = ElementShadow(color: SlideColor.white);
      expect(shape.copyWith(shadow: other).shadow, other);
      expect(shape, isNot(shape.copyWith(shadow: null)));
    });

    test('a shape without one writes no shadow', () {
      expect(
        ShapeElement(id: 'e', frame: frame).toJson(),
        isNot(contains('shadow')),
      );
    });
  });

  group('a picture shadow', () {
    test('round-trips through .qslide', () {
      final image = ImageElement(
        id: 'p',
        frame: frame,
        source: 'pics/a.png',
        shadow: shadow,
      );
      final deck = Presentation(
        slides: [
          Slide(id: 's', elements: [image]),
        ],
      );
      final read = only(QslideCodec.decode(QslideCodec.encode(deck)));
      expect(read, image);
      expect((read as ImageElement).copyWith(altText: 'x').shadow, shadow);
      expect(read.copyWith(shadow: null).shadow, isNull);
    });
  });

  group('migration', () {
    test('a shadow a version 5 file carried reads as a shadow', () {
      // A PowerPoint import writes version 1 with the shapes' shadows.
      for (final version in [1, 5]) {
        final read =
            only(
                  QslideCodec.fromJson(
                    deckWith({
                      'id': 'e',
                      'type': 'shape',
                      'kind': 'rectangle',
                      'frame': _frame,
                      'shadow': {
                        'color': '#0000007F',
                        'x': 3,
                        'y': 4,
                        'blur': 6,
                      },
                    }, version: version),
                  ),
                )
                as ShapeElement;
        expect(
          read.shadow,
          ElementShadow(
            color: const SlideColor(0x7F000000),
            x: 3,
            y: 4,
            blur: 6,
          ),
          reason: 'version $version',
        );
      }
    });
  });
}
