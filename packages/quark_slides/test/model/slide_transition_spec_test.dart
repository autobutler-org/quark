import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  group('SlideTransitionSpec', () {
    test('defaults to an instant cut of the default length', () {
      const t = SlideTransitionSpec();
      expect(t, SlideTransitionSpec.none);
      expect(t.kind, SlideTransitionKind.none);
      expect(t.direction, SlideTransitionDirection.left);
      expect(t.duration, const Duration(milliseconds: 500));
    });

    test('the duration is kept within 200 to 2000 ms', () {
      expect(const SlideTransitionSpec(durationMs: 50).durationMs, 200);
      expect(const SlideTransitionSpec(durationMs: 9000).durationMs, 2000);
      expect(const SlideTransitionSpec(durationMs: 1200).durationMs, 1200);
      final read = SlideTransitionSpec.fromJson(
        {'kind': 'fade', 'duration': -4},
        r'$',
      );
      expect(read.durationMs, 200);
    });

    test('writes only what differs from the defaults', () {
      expect(SlideTransitionSpec.none.toJson(), {'kind': 'none'});
      expect(const SlideTransitionSpec.fade().toJson(), {'kind': 'fade'});
      expect(
        const SlideTransitionSpec(
          kind: SlideTransitionKind.push,
          direction: SlideTransitionDirection.down,
          durationMs: 1500,
        ).toJson(),
        {'kind': 'push', 'direction': 'down', 'duration': 1500},
      );
    });

    test('every kind and direction round trips', () {
      for (final kind in SlideTransitionKind.values) {
        for (final direction in SlideTransitionDirection.values) {
          final t = SlideTransitionSpec(
            kind: kind,
            direction: direction,
            durationMs: 750,
          );
          expect(SlideTransitionSpec.fromJson(t.toJson(), r'$'), t);
        }
      }
    });

    test('an unknown direction reads as left', () {
      final t = SlideTransitionSpec.fromJson(
        {'kind': 'push', 'direction': 'diagonal'},
        r'$',
      );
      expect(t.direction, SlideTransitionDirection.left);
    });

    test('a mistyped duration names its path', () {
      expect(
        () => SlideTransitionSpec.fromJson(
          {'kind': 'fade', 'duration': 'slow'},
          r'$.transition',
        ),
        throwsA(
          isA<QslideFormatException>().having(
            (e) => e.path,
            'path',
            r'$.transition.duration',
          ),
        ),
      );
    });

    test('choosing a kind replaces an unknown one', () {
      final unknown = SlideTransitionSpec.fromJson({'kind': 'cube'}, r'$');
      expect(unknown.kind, SlideTransitionKind.none);
      expect(unknown.toJson(), {'kind': 'cube'});
      expect(unknown.copyWith(durationMs: 800).toJson(), {
        'kind': 'cube',
        'duration': 800,
      });
      expect(
        unknown.copyWith(kind: SlideTransitionKind.zoom).toJson(),
        {'kind': 'zoom'},
      );
    });

    test('reduced motion turns movement into the shortest fade', () {
      expect(SlideTransitionSpec.none.reducedMotion, SlideTransitionSpec.none);
      for (final kind in SlideTransitionKind.values.skip(1)) {
        final t = SlideTransitionSpec(kind: kind, durationMs: 1500);
        expect(
          t.reducedMotion,
          const SlideTransitionSpec.fade(durationMs: 200),
        );
      }
    });

    test('reversed moves the other way', () {
      expect(
        SlideTransitionDirection.values.map((d) => d.reversed),
        [
          SlideTransitionDirection.right,
          SlideTransitionDirection.left,
          SlideTransitionDirection.down,
          SlideTransitionDirection.up,
        ],
      );
      const push = SlideTransitionSpec(
        kind: SlideTransitionKind.push,
        durationMs: 900,
      );
      expect(push.reversed.direction, SlideTransitionDirection.right);
      expect(push.reversed.durationMs, 900);
    });

    test('only push and wipe have a direction', () {
      expect(
        SlideTransitionKind.values.where((k) => k.isDirectional),
        [SlideTransitionKind.push, SlideTransitionKind.wipe],
      );
    });
  });

  group('Presentation.transitionFor', () {
    test('a slide with none of its own follows the deck', () {
      const fade = SlideTransitionSpec.fade();
      const cut = SlideTransitionSpec.none;
      final deck = Presentation(
        defaultTransition: fade,
        slides: [
          const Slide(id: 'a'),
          const Slide(id: 'b', transition: cut),
        ],
      );
      expect(deck.transitionFor(deck.slides[0]), fade);
      // An explicit cut overrides the deck's fade, and is written.
      expect(deck.transitionFor(deck.slides[1]), cut);
      expect(deck.slides[1].toJson()['transition'], {'kind': 'none'});
      expect(deck.slides[0].toJson(), isNot(contains('transition')));
    });

    test('copyWith keeps or clears a slide transition', () {
      const slide = Slide(id: 'a', transition: SlideTransitionSpec.fade());
      expect(slide.copyWith(notes: 'n').transition, slide.transition);
      expect(slide.copyWith(transition: null).transition, isNull);
      expect(slide, isNot(slide.copyWith(transition: null)));
    });
  });
}
