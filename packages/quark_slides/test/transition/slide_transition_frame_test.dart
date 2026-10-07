import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  group('ease', () {
    test('starts at 0, ends at 1 and passes the middle at the middle', () {
      expect(SlideTransitionFrame.ease(0), 0);
      expect(SlideTransitionFrame.ease(0.5), 0.5);
      expect(SlideTransitionFrame.ease(1), 1);
    });

    test('starts and ends slowly', () {
      expect(SlideTransitionFrame.ease(0.1), closeTo(0.004, 1e-9));
      expect(SlideTransitionFrame.ease(0.9), closeTo(0.996, 1e-9));
      expect(SlideTransitionFrame.ease(0.25), closeTo(0.0625, 1e-9));
    });

    test('is symmetric and never runs backward', () {
      var last = 0.0;
      for (var i = 0; i <= 100; i++) {
        final t = i / 100;
        final e = SlideTransitionFrame.ease(t);
        expect(e, greaterThanOrEqualTo(last));
        expect(e + SlideTransitionFrame.ease(1 - t), closeTo(1, 1e-9));
        last = e;
      }
    });

    test('clamps outside 0 to 1', () {
      expect(SlideTransitionFrame.ease(-3), 0);
      expect(SlideTransitionFrame.ease(7), 1);
    });
  });

  group('progress', () {
    test('is the share of the duration that has gone, within 0 to 1', () {
      const d = Duration(milliseconds: 800);
      expect(SlideTransitionFrame.progress(Duration.zero, d), 0);
      expect(
        SlideTransitionFrame.progress(const Duration(milliseconds: 200), d),
        0.25,
      );
      expect(SlideTransitionFrame.progress(const Duration(seconds: 3), d), 1);
      expect(
        SlideTransitionFrame.progress(const Duration(milliseconds: -5), d),
        0,
      );
    });

    test('a zero duration is already over', () {
      expect(SlideTransitionFrame.progress(Duration.zero, Duration.zero), 1);
    });
  });

  group('at', () {
    SlideTransitionSpec spec(
      SlideTransitionKind kind, [
      SlideTransitionDirection direction = SlideTransitionDirection.left,
    ]) =>
        SlideTransitionSpec(kind: kind, direction: direction);

    test('every kind ends with the new slide whole and in place', () {
      for (final kind in SlideTransitionKind.values) {
        for (final direction in SlideTransitionDirection.values) {
          final end = SlideTransitionFrame.at(spec(kind, direction), 1);
          expect(end.incoming.opacity, 1, reason: '$kind');
          expect(end.incoming.offset, Offset.zero, reason: '$kind');
          expect(end.incoming.scale, 1, reason: '$kind');
          final clip = end.incoming.clip;
          expect(
            clip == null || clip == const Rect.fromLTRB(0, 0, 1, 1),
            isTrue,
            reason: '$kind $direction',
          );
        }
      }
    });

    test('every kind but none starts with the old slide alone', () {
      for (final kind in SlideTransitionKind.values.skip(1)) {
        for (final direction in SlideTransitionDirection.values) {
          final start = SlideTransitionFrame.at(spec(kind, direction), 0);
          expect(start.outgoing, SlideTransitionLayer.still);
          final incoming = start.incoming;
          final hidden = incoming.opacity == 0 ||
              incoming.offset.distance == 1 ||
              (incoming.clip != null && incoming.clip!.isEmpty);
          expect(hidden, isTrue, reason: '$kind $direction');
        }
      }
    });

    test('none shows the new slide at once', () {
      final f = SlideTransitionFrame.at(spec(SlideTransitionKind.none), 0);
      expect(f.incoming, SlideTransitionLayer.still);
      expect(f.outgoing.opacity, 0);
    });

    test('a fade brings the new slide up over the old', () {
      final f = SlideTransitionFrame.at(spec(SlideTransitionKind.fade), 0.4);
      expect(f.outgoing, SlideTransitionLayer.still);
      expect(f.incoming, const SlideTransitionLayer(opacity: 0.4));
    });

    test('a push moves both slides the way it travels', () {
      final cases = {
        SlideTransitionDirection.left: const Offset(-1, 0),
        SlideTransitionDirection.right: const Offset(1, 0),
        SlideTransitionDirection.up: const Offset(0, -1),
        SlideTransitionDirection.down: const Offset(0, 1),
      };
      cases.forEach((direction, travel) {
        final f = SlideTransitionFrame.at(
          spec(SlideTransitionKind.push, direction),
          0.25,
        );
        expect(f.outgoing.offset, travel * 0.25, reason: '$direction');
        expect(f.incoming.offset, travel * -0.75, reason: '$direction');
        expect(f.incoming.opacity, 1);
      });
    });

    test('a wipe uncovers the new slide from the edge it travels from', () {
      Rect? clip(SlideTransitionDirection d) => SlideTransitionFrame.at(
            spec(SlideTransitionKind.wipe, d),
            0.25,
          ).incoming.clip;
      expect(
        clip(SlideTransitionDirection.left),
        const Rect.fromLTRB(0.75, 0, 1, 1),
      );
      expect(
        clip(SlideTransitionDirection.right),
        const Rect.fromLTRB(0, 0, 0.25, 1),
      );
      expect(
        clip(SlideTransitionDirection.up),
        const Rect.fromLTRB(0, 0.75, 1, 1),
      );
      expect(
        clip(SlideTransitionDirection.down),
        const Rect.fromLTRB(0, 0, 1, 0.25),
      );
    });

    test('a zoom grows the new slide from the center as it fades in', () {
      final f = SlideTransitionFrame.at(spec(SlideTransitionKind.zoom), 0.5);
      expect(f.outgoing, SlideTransitionLayer.still);
      expect(f.incoming.opacity, 0.5);
      expect(f.incoming.scale, closeTo(0.65, 1e-9));
      expect(f.incoming.offset, Offset.zero);
    });

    test('progress outside 0 to 1 is clamped', () {
      final s = spec(SlideTransitionKind.push);
      expect(SlideTransitionFrame.at(s, -1), SlideTransitionFrame.at(s, 0));
      expect(SlideTransitionFrame.at(s, 2), SlideTransitionFrame.at(s, 1));
    });
  });
}
