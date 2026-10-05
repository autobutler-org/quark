import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/slide_present_controller.dart';
import 'package:quark/pages/slide_present_page.dart';
import 'package:quark/router.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../widgets/slides/present/fake_fullscreen.dart';
import '../support/tap_target_guidelines.dart' as tap;
import '../support/text_scale.dart';

/// Presenting (#1165) and the speaker notes it shows (#1166): the keys, taps
/// and swipes that step through the slides, the control bar that hides when
/// idle, the presenter view on a wide window, fullscreen, and Escape back to
/// the editor — on a phone and a desktop.
void main() {
  Presentation deck(int count) => Presentation(
    title: 'Deck',
    slides: [
      for (var i = 1; i <= count; i++)
        Slide(
          id: 's$i',
          notes: i == 2 ? '' : 'Remember point $i',
          elements: [
            TextBox(
              id: 't$i',
              frame: ElementFrame(x: 100, y: 100, width: 1700, height: 300),
              paragraphs: [TextParagraph.plain('Slide text $i')],
            ),
          ],
        ),
    ],
  );

  late FakeFullscreen screen;
  late GoRouter router;

  setUp(() => screen = FakeFullscreen());

  /// Pumps the page at `/slides/talks/Deck.qslide/present`, with the editor
  /// route beside it for Escape to land on.
  Future<SlidePresentController> pumpPresent(
    WidgetTester tester, {
    int start = 0,
    int slides = 3,
    Presentation? presentation,
  }) async {
    final controller = SlidePresentController(
      filePath: 'talks/Deck.qslide',
      startIndex: start,
      loadPresentation: (path, {serial}) async => presentation ?? deck(slides),
      fullscreen: screen,
    );
    router = GoRouter(
      initialLocation: AppRoutes.slidePresent('talks/Deck.qslide'),
      routes: [
        slidePresentRoute(
          builder: (filePath, serial, startIndex, initial) => SlidePresentPage(
            filePath: filePath,
            deviceSerial: serial,
            controller: controller,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.slides}/:path(.*)',
          builder: (_, state) => Text('editor ${state.pathParameters['path']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Takes the page down and stops its clock, so no timer outlives the test.
  Future<void> finish(WidgetTester tester, SlidePresentController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  Finder showing(int n) => find.text('Slide text $n', findRichText: true);

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('shows the slide fitted with its controls ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final c = await pumpPresent(tester);
      expect(showing(1), findsOneWidget);
      final canvas = tester.widget<SlideCanvas>(find.byType(SlideCanvas));
      expect(canvas.readOnly, isTrue);
      expect(find.text('Slide 1 of 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('slide_present_next')), findsOneWidget);
      expect(find.byKey(const ValueKey('slide_present_exit')), findsOneWidget);
      // The speaker's view needs room beside the slide.
      expect(
        find.byKey(const ValueKey('slide_present_presenter_view')),
        name == 'wide' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
      await finish(tester, c);
    });

    testWidgets('taps step forward on the right and back on the left ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final c = await pumpPresent(tester);
      final stage = find.byKey(const ValueKey('slide_present_stage'));
      final box = tester.getRect(stage);
      await tester.tapAt(Offset(box.left + box.width * 0.8, box.center.dy));
      await tester.pumpAndSettle();
      expect(c.index, 1);
      await tester.tapAt(Offset(box.left + box.width * 0.1, box.center.dy));
      await tester.pumpAndSettle();
      expect(c.index, 0);
      await tester.fling(stage, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(c.index, 1);
      await tester.fling(stage, const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(c.index, 0);
      await finish(tester, c);
    });
  }

  testWidgets('the keyboard steps, jumps and exits to the editor', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpPresent(tester, slides: 5);
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.enter,
    ]) {
      await press(tester, key);
    }
    expect(c.index, 4);
    expect(showing(5), findsOneWidget);
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.backspace,
    ]) {
      await press(tester, key);
    }
    expect(c.index, 1);
    await press(tester, LogicalKeyboardKey.end);
    expect(c.index, 4);
    await press(tester, LogicalKeyboardKey.home);
    expect(c.index, 0);

    await press(tester, LogicalKeyboardKey.keyF);
    expect(screen.isActive, isTrue);
    await press(tester, LogicalKeyboardKey.keyF);
    expect(screen.isActive, isFalse);

    await press(tester, LogicalKeyboardKey.keyF);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text('editor talks/Deck.qslide'), findsOneWidget);
    expect(screen.isActive, isFalse, reason: 'leaving ends fullscreen');
    c.dispose();
  });

  testWidgets('starts at the slide the link asks for', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpPresent(tester, start: 2);
    expect(showing(3), findsOneWidget);
    expect(find.text('Slide 3 of 3'), findsOneWidget);
    expect(
      tester
          .widget<QuarkBarIconButton>(
            find.byKey(const ValueKey('slide_present_next')),
          )
          .onPressed,
      isNull,
      reason: 'nothing after the last slide',
    );
    await finish(tester, c);
  });

  testWidgets('the controls hide when idle and come back on a move', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpPresent(tester);
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey('slide_present_controls')),
        )
        .opacity;
    expect(opacity(), 1);
    await tester.pump(SlidePresentController.controlsIdle);
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await finish(tester, c);
  });

  testWidgets('the presenter view shows the next slide, notes and clock', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpPresent(tester);
    await tester.tap(
      find.byKey(const ValueKey('slide_present_presenter_view')),
    );
    await tester.pumpAndSettle();
    expect(c.presenterView, isTrue);
    expect(find.text('Remember point 1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('slide_presenter_next')),
        matching: find.text('Slide text 2', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(find.text('00:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 65));
    expect(find.text('01:05'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('No notes for this slide.'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('End of presentation'), findsOneWidget);
    // The notes are read-only here.
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester, c);
  });

  /// A deck that pushes from slide to slide, except the last, which wipes.
  Presentation transitioning() {
    final d = deck(3);
    return d.copyWith(
      defaultTransition: const SlideTransitionSpec(
        kind: SlideTransitionKind.push,
        durationMs: 1000,
      ),
      slides: [
        ...d.slides.take(2),
        d.slides[2].copyWith(
          transition: const SlideTransitionSpec(
            kind: SlideTransitionKind.wipe,
            direction: SlideTransitionDirection.up,
            durationMs: 600,
          ),
        ),
      ],
    );
  }

  Finder layer(int n) => find.byKey(ValueKey('slide_transition_s$n'));

  Offset offsetOf(WidgetTester tester, int n) =>
      tester.widget<FractionalTranslation>(layer(n)).translation;

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('each step plays the transition of the slide it reaches '
        '($name)', (tester) async {
      tap.setViewport(tester, size);
      final c = await pumpPresent(tester, presentation: transitioning());
      expect(layer(1), findsOneWidget);

      // Forward: slide 2 pushes in from the right.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(showing(1), findsOneWidget);
      expect(showing(2), findsOneWidget);
      expect(offsetOf(tester, 1).dx, closeTo(-0.5, 1e-9));
      expect(offsetOf(tester, 2).dx, closeTo(0.5, 1e-9));
      await tester.pumpAndSettle();
      expect(showing(1), findsNothing);

      // Back: the same push, the other way.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.movedBack, isTrue);
      expect(offsetOf(tester, 1).dx, closeTo(-0.5, 1e-9));
      expect(offsetOf(tester, 2).dx, closeTo(0.5, 1e-9));
      await tester.pumpAndSettle();

      // A jump to the end plays the last slide's own wipe.
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final view = tester.widget<SlideTransitionView>(
        find.byType(SlideTransitionView),
      );
      expect(view.transition.kind, SlideTransitionKind.wipe);
      expect(view.reverse, isFalse);
      expect(offsetOf(tester, 3), Offset.zero);
      expect(showing(1), findsOneWidget);
      await tester.pumpAndSettle();
      expect(showing(1), findsNothing);
      expect(showing(3), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, c);
    });
  }

  testWidgets('the next-slide preview does not transition', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpPresent(tester, presentation: transitioning());
    await tester.tap(
      find.byKey(const ValueKey('slide_present_presenter_view')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final preview = find.byKey(const ValueKey('slide_presenter_next'));
    expect(
      find.descendant(of: preview, matching: find.byType(SlideTransitionView)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: preview,
        matching: find.text('Slide text 3', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(find.byType(SlideTransitionView), findsOneWidget);
    await tester.pumpAndSettle();
    await finish(tester, c);
  });

  testWidgets('a deck with no transitions cuts from slide to slide', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpPresent(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(showing(1), findsNothing, reason: 'no old slide lingering');
    expect(showing(2), findsOneWidget);
    await finish(tester, c);
  });

  for (final reduced in [true, false]) {
    testWidgets('reduced motion ${reduced ? 'on' : 'off'}: '
        '${reduced ? 'a push becomes a short fade' : 'the push moves'}', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      if (reduced) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      }
      final c = await pumpPresent(tester, presentation: transitioning());
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(showing(1), findsOneWidget);
      if (reduced) {
        expect(offsetOf(tester, 2), Offset.zero, reason: 'no movement');
        final opacity = tester.widget<Opacity>(
          find.descendant(of: layer(2), matching: find.byType(Opacity)).first,
        );
        expect(opacity.opacity, closeTo(0.5, 1e-9));
        await tester.pump(const Duration(milliseconds: 101));
        expect(showing(1), findsNothing, reason: 'over in 200 ms');
      } else {
        expect(offsetOf(tester, 2).dx, greaterThan(0.9));
        await tester.pump(const Duration(milliseconds: 101));
        expect(showing(1), findsOneWidget, reason: 'still pushing');
        await tester.pumpAndSettle();
      }
      await finish(tester, c);
    });
  }

  testLargeText('presents without overflow', (tester, size) async {
    final c = await pumpPresent(tester);
    if (size.width > 900) {
      await tester.tap(
        find.byKey(const ValueKey('slide_present_presenter_view')),
      );
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await finish(tester, c);
  });
}
