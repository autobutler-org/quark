import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/sample_presentation.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Matcher throwsFormatAt(String path) => throwsA(
      isA<QslideFormatException>().having((e) => e.path, 'path', path),
    );

void main() {
  group('golden sample.qslide', () {
    test('encoding the sample deck matches the fixture byte for byte', () {
      expect(
          QslideCodec.encode(samplePresentation()), fixture('sample.qslide'));
    });

    test('decoding the fixture gives the sample deck', () {
      expect(
          QslideCodec.decode(fixture('sample.qslide')), samplePresentation());
    });

    test('integral numbers are written without a fraction', () {
      final json = QslideCodec.toJson(samplePresentation());
      final size = json['size'] as Map<String, Object?>;
      expect(size['width'], isA<int>());
    });
  });

  group('forward compatibility', () {
    test('fields and elements a newer writer added survive a round trip', () {
      final source = fixture('future_fields.qslide');
      final encodedAgain = QslideCodec.encode(QslideCodec.decode(source));
      expect(jsonDecode(encodedAgain), jsonDecode(source));
    });

    test('an unknown element type reads as an UnknownElement', () {
      final deck = QslideCodec.decode(fixture('future_fields.qslide'));
      final chart = deck.slides.single.elementById('e3');
      expect(chart, isA<UnknownElement>());
      expect(chart!.type, 'chart');
      expect(chart.frame.width, 500);
    });

    test('a shape kind this version lacks is kept verbatim', () {
      final deck = QslideCodec.decode(fixture('future_fields.qslide'));
      expect(deck.slides.single.elementById('e4'), isA<UnknownElement>());
    });

    test('unknown fields survive an edit to the object holding them', () {
      final doc = SlideDocumentController(
        QslideCodec.decode(fixture('future_fields.qslide')),
      );
      doc.moveElements('s1', ['e1', 'e3'], 5, 5);
      final json = jsonDecode(QslideCodec.encode(doc.presentation)) as Map;
      final elements = (json['slides'] as List).single['elements'] as List;
      expect(elements[0]['shrinkToFit'], 'shrink');
      expect(elements[0]['frame'], {
        'x': 15,
        'y': 25,
        'width': 300,
        'height': 50,
        'locked': true,
      });
      expect(elements[2]['series'], isNotEmpty);
      expect(elements[2]['frame']['x'], 405);
    });

    test('a group keeps what it and its children do not understand', () {
      final doc = SlideDocumentController(
        QslideCodec.decode(fixture('future_fields.qslide')),
      );
      final group = doc.presentation.slides.single.elementById('e5');
      expect(group, isA<GroupElement>());
      expect((group! as GroupElement).children.first, isA<UnknownElement>());
      doc.moveElements('s1', ['e5'], 10, 0);
      doc.moveElements('s1', ['e7'], 0, 50);
      final json = jsonDecode(QslideCodec.encode(doc.presentation)) as Map;
      final saved = ((json['slides'] as List).single['elements'] as List)
          .firstWhere((e) => e['id'] == 'e5') as Map;
      expect(saved['locked'], isTrue);
      final children = saved['children'] as List;
      expect(children[0]['series'], isNotEmpty);
      expect(children[1]['glow'], 4);
      expect(saved['frame']['x'], 610);
      // The group refitted around its moved child.
      expect(saved['frame']['height'], 250);
    });

    test('a reader that predates groups keeps one verbatim', () {
      // What an older version sees: a type it does not know.
      final group = SlideElement.fromJson({
        'id': 'g',
        'type': 'group-v2',
        'frame': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
        'children': [],
      }, r'$');
      expect(group, isA<UnknownElement>());
      expect(group.toJson()['children'], isEmpty);
    });

    test('a dash this version cannot read draws solid and is kept', () {
      final deck = QslideCodec.decode(fixture('future_fields.qslide'));
      final shape = deck.slides.single.elementById('e2') as ShapeElement;
      expect(shape.stroke!.dash, StrokeDash.solid);
      expect(shape.stroke!.toJson()['dash'], [4, 2]);
      final named = Stroke.fromJson({'dash': 'zigzag'}, r'$');
      expect(named.dash, StrokeDash.solid);
      expect(named.toJson()['dash'], 'zigzag');
      // Choosing a dash replaces the one kept.
      expect(
        shape.stroke!.copyWith(dash: StrokeDash.dot).toJson()['dash'],
        'dot',
      );
      expect(
        shape.stroke!.copyWith(dash: StrokeDash.solid).toJson(),
        isNot(contains('dash')),
      );
    });

    test('a newer schemaVersion is refused rather than misread', () {
      expect(
        () => QslideCodec.decode(fixture('newer_schema.qslide')),
        throwsFormatAt(r'$.schemaVersion'),
      );
    });

    test('an unknown alignment, fit, anchor or list falls back to the default',
        () {
      final deck = QslideCodec.fromJson({
        'schemaVersion': 1,
        'slides': [
          {
            'id': 's',
            'elements': [
              {
                'id': 't',
                'type': 'text',
                'frame': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
                'anchor': 'baseline',
                'autoFit': 'wrap',
                'paragraphs': [
                  {'runs': [], 'align': 'distributed', 'list': 'roman'},
                ],
              },
              {
                'id': 'i',
                'type': 'image',
                'frame': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
                'source': 'a.png',
                'fit': 'tile',
              },
            ],
          },
        ],
      });
      final slide = deck.slides.single;
      expect(
        (slide.elements[0] as TextBox).paragraphs.single.alignment,
        TextAlignment.start,
      );
      expect((slide.elements[1] as ImageElement).fit, ImageFit.contain);
      final box = slide.elements[0] as TextBox;
      expect(box.anchor, TextAnchor.top);
      expect(box.autoFit, TextAutoFit.grow);
      expect(box.paragraphs.single.list, TextListStyle.none);
    });
  });

  group('defaults', () {
    test('a minimal file reads with the widescreen size and no slides', () {
      final deck = QslideCodec.decode('{"schemaVersion": 1}');
      expect(deck.title, '');
      expect(deck.size, SlideSize.widescreen);
      expect(deck.size.aspectRatio, closeTo(16 / 9, 1e-9));
      expect(deck.theme, isNull);
      expect(deck.slides, isEmpty);
    });

    test('an empty presentation round trips', () {
      final deck = Presentation();
      expect(QslideCodec.decode(QslideCodec.encode(deck)), deck);
    });

    test('a line without a stroke gets the default one', () {
      final deck = QslideCodec.fromJson({
        'schemaVersion': 1,
        'slides': [
          {
            'id': 's',
            'elements': [
              {
                'id': 'l',
                'type': 'line',
                'frame': {'x': 0, 'y': 0, 'width': 1, 'height': 0},
              },
            ],
          },
        ],
      });
      expect(
          (deck.slides.single.elements.single as LineElement).stroke, Stroke());
    });
  });

  group('shapes, lines and images', () {
    Presentation read(List<Map<String, Object?>> elements) =>
        QslideCodec.fromJson({
          'schemaVersion': 1,
          'slides': [
            {'id': 's', 'elements': elements},
          ],
        });
    const frame = {'x': 0, 'y': 0, 'width': 10, 'height': 10};

    test('opacity, dash and corner radius default when absent', () {
      final deck = read([
        {'id': 'a', 'type': 'shape', 'kind': 'rectangle', 'frame': frame},
        {'id': 'b', 'type': 'line', 'frame': frame},
      ]);
      final [shape as ShapeElement, line as LineElement] =
          deck.slides.single.elements;
      expect(shape.opacity, 1);
      expect(shape.cornerRadius, isNull);
      expect(line.opacity, 1);
      expect(line.stroke.dash, StrokeDash.solid);
      // Defaults are not written out.
      final json = shape.toJson();
      expect(json.containsKey('opacity'), isFalse);
      expect(json.containsKey('cornerRadius'), isFalse);
    });

    test('an opacity outside 0–1 and a negative radius are clamped', () {
      final deck = read([
        {
          'id': 'a',
          'type': 'shape',
          'kind': 'roundedRectangle',
          'frame': frame,
          'opacity': 3,
          'cornerRadius': -4,
        },
        {'id': 'b', 'type': 'line', 'frame': frame, 'opacity': -1},
      ]);
      final [shape as ShapeElement, line as LineElement] =
          deck.slides.single.elements;
      expect(shape.opacity, 1);
      expect(shape.cornerRadius, 0);
      expect(line.opacity, 0);
    });

    test('every dash round trips', () {
      for (final dash in StrokeDash.values) {
        final stroke = Stroke(dash: dash);
        expect(Stroke.fromJson(stroke.toJson(), r'$'), stroke);
      }
    });

    test('a non-numeric opacity names its path', () {
      expect(
        () => read([
          {
            'id': 'a',
            'type': 'line',
            'frame': frame,
            'opacity': 'half',
          },
        ]),
        throwsFormatAt(r'$.slides[0].elements[0].opacity'),
      );
    });
  });

  group('ImageSource', () {
    test('an asset: reference is an uploaded asset, anything else a path', () {
      expect(
        ImageSource.parse('asset:abc'),
        const UploadedAssetImage('abc'),
      );
      expect(
        ImageSource.parse('photos/dog.jpg'),
        const QuarkFileImage('photos/dog.jpg'),
      );
      expect(ImageSource.parse('/a/asset:b'), isA<QuarkFileImage>());
    });

    test('ref round trips through parse', () {
      for (final source in const [
        QuarkFileImage('photos/dog.jpg'),
        UploadedAssetImage('logo-1'),
      ]) {
        expect(ImageSource.parse(source.ref), source);
      }
      expect(const UploadedAssetImage('x').ref, 'asset:x');
      expect(const QuarkFileImage('x'), isNot(const UploadedAssetImage('x')));
    });

    test('the sample deck reads both kinds', () {
      final [s1, s2, ...] = samplePresentation().slides;
      expect(
        (s2.elementById('e3') as ImageElement).imageSource,
        const QuarkFileImage('photos/dog.jpg'),
      );
      expect(
        (s1.elementById('e7') as ImageElement).imageSource,
        const UploadedAssetImage('logo-1'),
      );
    });
  });

  group('malformed files', () {
    test('text that is not JSON', () {
      expect(() => QslideCodec.decode('{nope'), throwsFormatAt(r'$'));
    });

    test('a root that is not an object', () {
      expect(() => QslideCodec.decode('[]'), throwsFormatAt(r'$'));
    });

    test('a missing schemaVersion', () {
      expect(
        () => QslideCodec.decode('{"slides": []}'),
        throwsFormatAt(r'$.schemaVersion'),
      );
    });

    test('a schemaVersion that is not a positive integer', () {
      for (final version in ['"1"', '0', '1.5']) {
        expect(
          () => QslideCodec.decode('{"schemaVersion": $version}'),
          throwsFormatAt(r'$.schemaVersion'),
          reason: version,
        );
      }
    });

    test('the error names the exact field that was wrong', () {
      final json = QslideCodec.toJson(samplePresentation());
      final slide = (json['slides'] as List)[1] as Map<String, Object?>;
      final element = (slide['elements'] as List)[0] as Map<String, Object?>;
      (element['frame'] as Map<String, Object?>)['width'] = 'wide';
      expect(
        () => QslideCodec.fromJson(jsonDecode(jsonEncode(json))),
        throwsFormatAt(r'$.slides[1].elements[0].frame.width'),
      );
    });

    test('a negative frame size', () {
      expect(
        () => QslideCodec.fromJson({
          'schemaVersion': 1,
          'slides': [
            {
              'id': 's',
              'elements': [
                {
                  'id': 'e',
                  'type': 'shape',
                  'kind': 'rectangle',
                  'frame': {'x': 0, 'y': 0, 'width': -1, 'height': 1},
                },
              ],
            },
          ],
        }),
        throwsFormatAt(r'$.slides[0].elements[0].frame'),
      );
    });

    test('an element without an id', () {
      expect(
        () => QslideCodec.fromJson({
          'schemaVersion': 1,
          'slides': [
            {
              'id': 's',
              'elements': [
                {'type': 'shape'},
              ],
            },
          ],
        }),
        throwsFormatAt(r'$.slides[0].elements[0].id'),
      );
    });

    test('a bad color', () {
      expect(
        () => QslideCodec.fromJson({
          'schemaVersion': 1,
          'slides': [
            {
              'id': 's',
              'background': {'color': 'red'},
            },
          ],
        }),
        throwsFormatAt(r'$.slides[0].background.color'),
      );
    });
  });
}
