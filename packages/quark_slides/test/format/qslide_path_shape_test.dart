// cspell:words diagStripe round2SameRect insertable rtTriangle wR
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  final frame = ElementFrame(x: 10, y: 20, width: 30, height: 40);
  const contour = ShapeContour(
    commands: [
      ShapeMove(0, 1),
      ShapeLine(0, 0),
      ShapeQuad(0.2, 0.2, 0.5, 0),
      ShapeCubic(0.6, 0.1, 0.8, 0.2, 1, 0.5),
      ShapeArc(wR: 0.25, hR: 0.5, start: 0, swing: 90),
      ShapeClose(),
    ],
  );

  Presentation deckOf(ShapeElement shape) => Presentation(
    slides: [
      Slide(id: 's', elements: [shape]),
    ],
  );

  test('a preset and its adjust values round-trip with the keys sorted', () {
    final shape = ShapeElement(
      id: 'e',
      frame: frame,
      kind: ShapeKind.path,
      preset: 'round2SameRect',
      adjust: const {'adj2': 0, 'adj1': 4129},
      fill: SlideColor.parse('#3366FF'),
    );
    final saved = QslideCodec.encode(deckOf(shape));
    expect(saved.indexOf('"adj1"'), lessThan(saved.indexOf('"adj2"')));
    expect(saved, isNot(contains('"schemaVersion": 7')));
    final read =
        QslideCodec.decode(saved).slides.single.elements.single as ShapeElement;
    expect(read, shape);
    expect(read.adjust['adj1'], 4129);
    expect(read.adjust['adj2'], 0);
  });

  test('contours round-trip, including an arc', () {
    final shape = ShapeElement(
      id: 'e',
      frame: frame,
      kind: ShapeKind.path,
      contours: const [
        contour,
        ShapeContour(commands: [ShapeLine(1, 1)], fill: false, stroke: false),
      ],
    );
    final read =
        QslideCodec.decode(
              QslideCodec.encode(deckOf(shape)),
            ).slides.single.elements.single
            as ShapeElement;
    expect(read, shape);
    expect(read.contours[1].fill, isFalse);
    expect(read.contours[1].stroke, isFalse);
  });

  test('a rectangle file gains no preset, adjust or contour fields', () {
    final shape = ShapeElement(id: 'e', frame: frame);
    final json = shape.toJson();
    expect(json.containsKey('preset'), isFalse);
    expect(json.containsKey('adjust'), isFalse);
    expect(json.containsKey('contours'), isFalse);
    final read =
        QslideCodec.decode(
              QslideCodec.encode(deckOf(shape)),
            ).slides.single.elements.single
            as ShapeElement;
    expect(read.preset, isNull);
    expect(read.adjust, isEmpty);
    expect(read.contours, isEmpty);
    expect(read, shape);
  });

  test('a version 1 file can already carry a path shape', () {
    final deck = QslideCodec.fromJson({
      'schemaVersion': 1,
      'slides': [
        {
          'id': 's',
          'elements': [
            {
              'id': 'e',
              'type': 'shape',
              'kind': 'path',
              'preset': 'rtTriangle',
              'frame': {'x': 0, 'y': 0, 'width': 10, 'height': 10},
            },
          ],
        },
      ],
    });
    final shape = deck.slides.single.elements.single as ShapeElement;
    expect(shape.kind, ShapeKind.path);
    expect(shape.preset, 'rtTriangle');
  });

  test('restyling to another kind drops the preset and the contours', () {
    final shape = ShapeElement(
      id: 'e',
      frame: frame,
      kind: ShapeKind.path,
      preset: 'diagStripe',
      adjust: const {'adj': 50000},
      contours: const [contour],
    );
    final star = shape.copyWith(kind: ShapeKind.star);
    expect(star.kind, ShapeKind.star);
    expect(star.preset, isNull);
    expect(star.adjust, isEmpty);
    expect(star.contours, isEmpty);
    expect(shape.copyWith(kind: ShapeKind.path).preset, 'diagStripe');
    expect(shape.copyWith(fill: SlideColor.black).preset, 'diagStripe');
    expect(shape.copyWith(fill: SlideColor.black).contours, isNotEmpty);
  });

  test('an unknown contour command is refused', () {
    expect(
      () => QslideCodec.fromJson({
        'schemaVersion': 5,
        'slides': [
          {
            'id': 's',
            'elements': [
              {
                'id': 'e',
                'type': 'shape',
                'kind': 'path',
                'frame': {'x': 0, 'y': 0, 'width': 10, 'height': 10},
                'contours': [
                  {
                    'commands': [
                      {'op': 'spiral'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      }),
      throwsA(isA<QslideFormatException>()),
    );
  });

  test('a path is a kind to read, not a tool to draw with', () {
    expect(ShapeKind.insertable, isNot(contains(ShapeKind.path)));
    expect(
      ShapeKind.insertable.toSet(),
      ShapeKind.values.toSet().difference({ShapeKind.path}),
    );
  });
}
