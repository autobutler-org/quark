import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/sample_presentation.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  test('this version writes schema 2', () {
    expect(QslideCodec.schemaVersion, 2);
    expect(QslideCodec.toJson(Presentation())['schemaVersion'], 2);
  });

  group('from schema version 1', () {
    test('the golden v1 file reads with no theme and blank layouts', () {
      final deck = QslideCodec.decode(fixture('v1_sample.qslide'));
      expect(deck, legacySamplePresentation());
      expect(deck.theme, isNull);
      expect(deck.slides.map((s) => s.layoutId), everyElement('blank'));
    });

    test('it saves as version 2, without the old theme reference', () {
      final json = QslideCodec.toJson(
        QslideCodec.decode(fixture('v1_sample.qslide')),
      );
      expect(json['schemaVersion'], 2);
      expect(json, isNot(contains('theme')));
      final again = QslideCodec.decode(jsonEncode(json));
      expect(again, legacySamplePresentation());
    });

    test('a theme reference naming a built-in theme becomes that theme', () {
      final deck = QslideCodec.fromJson({
        'schemaVersion': 1,
        'theme': 'dark',
        'slides': [],
      });
      expect(deck.theme, SlideThemes.dark);
    });

    test('fields version 1 did not know still survive the migration', () {
      final deck = QslideCodec.fromJson({
        'schemaVersion': 1,
        'comments': ['kept'],
        'slides': [],
      });
      expect(QslideCodec.toJson(deck)['comments'], ['kept']);
    });
  });

  group('schema version 2', () {
    test('the golden sample carries its theme, layouts and role colors', () {
      final json = jsonDecode(fixture('sample.qslide')) as Map;
      expect(json['schemaVersion'], 2);
      expect((json['theme'] as Map)['id'], 'sample');
      final deck = QslideCodec.decode(fixture('sample.qslide'));
      expect(deck.theme, sampleTheme());
      final slide = deck.slideById('s4')!;
      expect(slide.layoutId, 'titleAndContent');
      final title = slide.elementById('e13')! as TextBox;
      expect(title.slot, 'title');
      expect(title.textRole, ThemeTextRole.title);
      expect(
        title.paragraphs.single.runs.single.color,
        const SlideColor.theme(ThemeColor.accent2),
      );
      expect(
        (slide.elementById('e15')! as ShapeElement).fill,
        const SlideColor.theme(ThemeColor.accent1),
      );
    });

    test('a theme, layout or role a newer writer added survives', () {
      final source = fixture('future_fields.qslide');
      final deck = QslideCodec.decode(source);
      expect(deck.theme!.id, 'ours');
      expect(deck.theme!.extra, contains('gradients'));
      expect(deck.slides.single.layoutId, 'title-and-body');
      final saved = jsonDecode(QslideCodec.encode(deck)) as Map;
      final theme = saved['theme'] as Map;
      expect((theme['colors'] as Map)['accent7'], '#123456');
      expect((theme['title'] as Map)['letterSpacing'], 2);
      expect((theme['shapes'] as Map)['shadow'], isTrue);
      expect((saved['slides'] as List).single['layout'], 'title-and-body');
    });

    test('a text role this version does not know reads as body', () {
      final box = SlideElement.fromJson({
        'id': 't',
        'type': 'text',
        'frame': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
        'textRole': 'caption',
      }, r'$') as TextBox;
      expect(box.textRole, ThemeTextRole.body);
    });
  });
}
