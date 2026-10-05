import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/canvas_harness.dart';

const _push = SlideTransitionSpec(
  kind: SlideTransitionKind.push,
  durationMs: 1000,
);

final _deck = Presentation(
  slides: [
    for (final id in ['a', 'b', 'c'])
      Slide(
        id: id,
        background: SlideBackground(
          color: SlideColor(id == 'a' ? 0xFFFF0000 : 0xFF0000FF),
        ),
      ),
  ],
);

/// Shows [slideId] of [_deck] in a [SlideTransitionView], drawn by a
/// read-only canvas as presenting does.
Future<void> _show(
  WidgetTester tester,
  Size size,
  String slideId, {
  SlideTransitionSpec transition = _push,
  bool reverse = false,
  bool disableAnimations = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final slide = _deck.slideById(slideId)!;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: Scaffold(
          body: SlideTransitionView(
            slideId: slideId,
            transition: transition,
            reverse: reverse,
            child: SlideCanvas.readOnly(slide: slide, size: _deck.size),
          ),
        ),
      ),
    ),
  );
  // A transition's clock starts on the frame after the one that began it.
  await tester.pump();
}

Finder _layer(String id) => find.byKey(ValueKey('slide_transition_$id'));

Offset _offset(WidgetTester tester, String id) =>
    tester.widget<FractionalTranslation>(_layer(id)).translation;

double _opacity(WidgetTester tester, String id) => tester
    .widget<Opacity>(
      find.descendant(of: _layer(id), matching: find.byType(Opacity)).first,
    )
    .opacity;

double _scale(WidgetTester tester, String id) => tester
    .widget<Transform>(
      find.descendant(of: _layer(id), matching: find.byType(Transform)).first,
    )
    .transform
    .storage[0];

Rect? _clip(WidgetTester tester, String id) {
  final clip = tester.widget<ClipRect>(
    find.descendant(of: _layer(id), matching: find.byType(ClipRect)).first,
  );
  return (clip.clipper! as dynamic).fraction as Rect?;
}

void main() {
  testBothViewports('the first slide simply appears', (tester, size) async {
    await _show(tester, size, 'a');
    expect(_layer('a'), findsOneWidget);
    expect(_offset(tester, 'a'), Offset.zero);
    expect(_opacity(tester, 'a'), 1);
    expect(find.byType(SlideCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a push moves both slides across and ends on the new one',
      (tester, size) async {
    await _show(tester, size, 'a');
    await _show(tester, size, 'b');
    expect(find.byType(SlideCanvas), findsNWidgets(2));
    expect(_offset(tester, 'a'), Offset.zero);
    expect(_offset(tester, 'b'), const Offset(1, 0));

    await tester.pump(const Duration(milliseconds: 500));
    expect(_offset(tester, 'a').dx, closeTo(-0.5, 1e-9));
    expect(_offset(tester, 'b').dx, closeTo(0.5, 1e-9));

    await tester.pump(const Duration(milliseconds: 501));
    expect(_layer('a'), findsNothing);
    expect(_offset(tester, 'b'), Offset.zero);
    expect(find.byType(SlideCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('stepping back plays the push the other way',
      (tester, size) async {
    await _show(tester, size, 'b');
    await _show(tester, size, 'a', reverse: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_offset(tester, 'b').dx, closeTo(0.5, 1e-9));
    expect(_offset(tester, 'a').dx, closeTo(-0.5, 1e-9));
    await tester.pumpAndSettle();
  });

  testBothViewports('a fade brings the new slide up over the old',
      (tester, size) async {
    await _show(tester, size, 'a');
    await _show(
      tester,
      size,
      'b',
      transition: const SlideTransitionSpec.fade(durationMs: 400),
    );
    expect(_opacity(tester, 'b'), 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester, 'b'), closeTo(0.5, 1e-9));
    expect(_opacity(tester, 'a'), 1);
    await tester.pumpAndSettle();
    expect(_layer('a'), findsNothing);
  });

  testBothViewports('a wipe uncovers and a zoom grows the new slide',
      (tester, size) async {
    await _show(tester, size, 'a');
    await _show(
      tester,
      size,
      'b',
      transition: const SlideTransitionSpec(
        kind: SlideTransitionKind.wipe,
        direction: SlideTransitionDirection.down,
        durationMs: 1000,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_clip(tester, 'b'), const Rect.fromLTRB(0, 0, 1, 0.5));
    await tester.pumpAndSettle();

    await _show(
      tester,
      size,
      'c',
      transition: const SlideTransitionSpec(
        kind: SlideTransitionKind.zoom,
        durationMs: 1000,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_scale(tester, 'c'), closeTo(0.65, 1e-6));
    expect(_opacity(tester, 'c'), closeTo(0.5, 1e-9));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testBothViewports('none is an instant cut', (tester, size) async {
    await _show(tester, size, 'a');
    await _show(tester, size, 'b', transition: SlideTransitionSpec.none);
    expect(_layer('a'), findsNothing);
    expect(_offset(tester, 'b'), Offset.zero);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testBothViewports(
      'a change mid-transition carries on from the arriving slide',
      (tester, size) async {
    await _show(tester, size, 'a');
    await _show(tester, size, 'b');
    await tester.pump(const Duration(milliseconds: 300));
    await _show(tester, size, 'c');
    expect(_layer('a'), findsNothing);
    expect(_layer('b'), findsOneWidget);
    expect(_offset(tester, 'c'), const Offset(1, 0));
    await tester.pumpAndSettle();
    expect(_layer('b'), findsNothing);
    expect(_layer('c'), findsOneWidget);
  });

  group('reduced motion', () {
    testBothViewports('"Remove animations" makes a push a short fade',
        (tester, size) async {
      await _show(tester, size, 'a', disableAnimations: true);
      await _show(tester, size, 'b', disableAnimations: true);
      expect(_offset(tester, 'b'), Offset.zero);
      expect(_opacity(tester, 'b'), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_offset(tester, 'a'), Offset.zero);
      expect(_offset(tester, 'b'), Offset.zero);
      expect(_opacity(tester, 'b'), closeTo(0.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 101));
      expect(_layer('a'), findsNothing);
    });

    testBothViewports('iOS Reduce Motion makes a push a short fade',
        (tester, size) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _show(tester, size, 'a');
      await _show(tester, size, 'b');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_offset(tester, 'b'), Offset.zero);
      expect(_opacity(tester, 'b'), closeTo(0.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 101));
      expect(_layer('a'), findsNothing);
    });

    testBothViewports(
        'the platform\'s "Remove animations" fades for 200 ms too',
        (tester, size) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _show(tester, size, 'a', disableAnimations: true);
      await _show(tester, size, 'b', disableAnimations: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_opacity(tester, 'b'), closeTo(0.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 101));
      expect(_layer('a'), findsNothing);
    });

    testBothViewports('turning it on mid-transition finishes it at once',
        (tester, size) async {
      await _show(tester, size, 'a');
      await _show(tester, size, 'b');
      await tester.pump(const Duration(milliseconds: 300));
      expect(_layer('a'), findsOneWidget);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pump();
      expect(_layer('a'), findsNothing);
      expect(_offset(tester, 'b'), Offset.zero);
    });

    testBothViewports('off, the push moves as it was set',
        (tester, size) async {
      await _show(tester, size, 'a');
      await _show(tester, size, 'b');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_offset(tester, 'b').dx, greaterThan(0.9));
      expect(_opacity(tester, 'b'), 1);
      await tester.pumpAndSettle();
    });

    testBothViewports('a cut stays a cut', (tester, size) async {
      await _show(tester, size, 'a', disableAnimations: true);
      await _show(
        tester,
        size,
        'b',
        transition: SlideTransitionSpec.none,
        disableAnimations: true,
      );
      expect(_layer('a'), findsNothing);
    });
  });
}
