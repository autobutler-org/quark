import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/sample_presentation.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  test('this version writes schema 3', () {
    expect(QslideCodec.schemaVersion, 3);
    expect(QslideCodec.toJson(Presentation())['schemaVersion'], 3);
  });

  group('from schema version 1', () {
    test('the golden v1 file reads with no theme and blank layouts', () {
      final deck = QslideCodec.decode(fixture('v1_sample.qslide'));
      expect(deck, legacySamplePresentation());
      expect(deck.theme, isNull);
      expect(deck.slides.map((s) => s.layoutId), everyElement('blank'));
    });

    test('it saves as version 3, without the old theme reference', () {
      final json = QslideCodec.toJson(
        QslideCodec.decode(fixture('v1_sample.qslide')),
      );
      expect(json['schemaVersion'], 3);
      expect(json, isNot(contains('theme')));
      expect(json, isNot(contains('transition')));
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

  group('from schema version 2', () {
    // The sample deck as it was before transitions: the v2 golden file.
    Presentation v2Sample() {
      final deck = samplePresentation();
      return deck.copyWith(
        defaultTransition: SlideTransitionSpec.none,
        slides: [for (final s in deck.slides) s.copyWith(transition: null)],
      );
    }

    test('the golden v2 file reads with every slide cutting', () {
      final json = jsonDecode(fixture('v2_sample.qslide')) as Map;
      expect(json['schemaVersion'], 2);
      final deck = QslideCodec.decode(fixture('v2_sample.qslide'));
      expect(deck, v2Sample());
      expect(deck.defaultTransition, SlideTransitionSpec.none);
      expect(
        deck.slides.map(deck.transitionFor),
        everyElement(SlideTransitionSpec.none),
      );
    });

    test('it saves as version 3 with no transition written', () {
      final json = QslideCodec.toJson(
        QslideCodec.decode(fixture('v2_sample.qslide')),
      );
      expect(json['schemaVersion'], 3);
      expect(json, isNot(contains('transition')));
      expect(
        (json['slides'] as List).cast<Map>(),
        everyElement(isNot(contains('transition'))),
      );
      expect(QslideCodec.decode(jsonEncode(json)), v2Sample());
    });

    test('fields version 2 did not know still survive the migration', () {
      final deck = QslideCodec.fromJson({
        'schemaVersion': 2,
        'comments': ['kept'],
        'slides': [
          {'id': 's1', 'reactions': 3},
        ],
      });
      final json = QslideCodec.toJson(deck);
      expect(json['comments'], ['kept']);
      expect((json['slides'] as List).single['reactions'], 3);
    });

    test('a version 1 file with transitions reads them after migrating', () {
      // A PowerPoint import writes version 1 with the slides' transitions.
      final deck = QslideCodec.fromJson({
        'schemaVersion': 1,
        'slides': [
          {
            'id': 's1',
            'transition': {'kind': 'push', 'direction': 'up'},
          },
        ],
      });
      expect(
        deck.slides.single.transition,
        const SlideTransitionSpec(
          kind: SlideTransitionKind.push,
          direction: SlideTransitionDirection.up,
        ),
      );
    });
  });

  group('schema version 3', () {
    test('the golden sample carries its transitions', () {
      final json = jsonDecode(fixture('sample.qslide')) as Map;
      expect(json['schemaVersion'], 3);
      expect(json['transition'], {'kind': 'fade', 'duration': 700});
      final deck = QslideCodec.decode(fixture('sample.qslide'));
      expect(
          deck.defaultTransition,
          const SlideTransitionSpec.fade(
            durationMs: 700,
          ));
      expect(deck.transitionFor(deck.slideById('s1')!), deck.defaultTransition);
      expect(
        deck.transitionFor(deck.slideById('s4')!),
        const SlideTransitionSpec(
          kind: SlideTransitionKind.wipe,
          direction: SlideTransitionDirection.right,
          durationMs: 1200,
        ),
      );
    });

    test('a transition kind or field a newer writer added survives', () {
      final deck = QslideCodec.fromJson({
        'schemaVersion': 3,
        'transition': {'kind': 'cube', 'duration': 900, 'sound': 'chime'},
        'slides': [
          {
            'id': 's1',
            'transition': {'kind': 'fade', 'easing': 'bounce'},
          },
        ],
      });
      // An unknown kind plays as a cut and is written back as it was.
      expect(deck.defaultTransition.kind, SlideTransitionKind.none);
      expect(deck.defaultTransition.durationMs, 900);
      final saved = jsonDecode(QslideCodec.encode(deck)) as Map;
      expect(saved['transition'], {
        'kind': 'cube',
        'duration': 900,
        'sound': 'chime',
      });
      expect((saved['slides'] as List).single['transition'], {
        'kind': 'fade',
        'easing': 'bounce',
      });
    });
  });

  group('schema version 2 features', () {
    test('the golden sample carries its theme, layouts and role colors', () {
      final json = jsonDecode(fixture('sample.qslide')) as Map;
      expect(json['schemaVersion'], 3);
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
