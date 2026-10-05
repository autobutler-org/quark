import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/slide_present_controller.dart';
import 'package:quark/utils/fullscreen.dart';
import 'package:quark_slides/quark_slides.dart';

import '../widgets/slides/present/fake_fullscreen.dart';

/// Presenting a `.qslide` (#1165): loading or taking the editor's copy,
/// stepping through the slides, the presenter view and its clock, the
/// controls that hide when idle, and fullscreen.
void main() {
  Presentation deck(int count) => Presentation(
    title: 'Deck',
    slides: [
      for (var i = 1; i <= count; i++) Slide(id: 's$i', notes: 'Notes $i'),
    ],
  );

  SlidePresentController controllerFor({
    Presentation? initial,
    int startIndex = 0,
    Object? loadFailure,
    FullscreenControl? fullscreen,
  }) => SlidePresentController(
    filePath: 'talks/deck.qslide',
    deviceSerial: 'usb1',
    startIndex: startIndex,
    initial: initial,
    loadPresentation: (path, {serial}) async {
      expect(path, 'talks/deck.qslide');
      expect(serial, 'usb1');
      if (loadFailure != null) throw loadFailure;
      return deck(3);
    },
    fullscreen: fullscreen ?? FakeFullscreen(),
  );

  test('loads the presentation and starts at the slide asked for', () async {
    final c = controllerFor(startIndex: 1);
    expect(c.isLoading, isTrue);
    await c.load();
    expect(c.isLoading, isFalse);
    expect(c.index, 1);
    expect(c.currentSlide?.id, 's2');
    expect(c.nextSlide?.id, 's3');
    expect(c.position, 'Slide 2 of 3');
    c.dispose();
  });

  test('a start past the end is the last slide', () async {
    final c = controllerFor(startIndex: 9);
    await c.load();
    expect(c.index, 2);
    expect(c.nextSlide, isNull);
    c.dispose();
  });

  test('the editor\'s copy is shown without loading', () async {
    final c = controllerFor(
      initial: deck(2),
      loadFailure: Exception('not called'),
    );
    expect(c.isLoading, isFalse);
    expect(c.slides, hasLength(2));
    await c.load();
    expect(c.loadError, isNull);
    expect(c.slides, hasLength(2));
    c.dispose();
  });

  test('a failed load is kept as the thrown object', () async {
    final failure = Exception('offline');
    final c = controllerFor(loadFailure: failure);
    await c.load();
    expect(c.loadError, same(failure));
    expect(c.currentSlide, isNull);
    c.dispose();
  });

  test('steps stop at the first and last slides', () async {
    final c = controllerFor();
    await c.load();
    c.previous();
    expect(c.index, 0);
    c.next();
    c.next();
    c.next();
    expect(c.index, 2);
    expect(c.isLast, isTrue);
    c.first();
    expect(c.index, 0);
    c.last();
    expect(c.index, 2);
    c.dispose();
  });

  test('each slide plays its own transition, or the deck\'s', () async {
    const fade = SlideTransitionSpec.fade();
    const push = SlideTransitionSpec(kind: SlideTransitionKind.push);
    final d = deck(3);
    final c = controllerFor(
      initial: d.copyWith(
        defaultTransition: fade,
        slides: [
          d.slides[0],
          d.slides[1].copyWith(transition: push),
          d.slides[2],
        ],
      ),
    );
    expect(c.transition, fade);
    expect(c.movedBack, isFalse);
    c.next();
    expect(c.transition, push);
    expect(c.movedBack, isFalse);
    c.last();
    expect(c.transition, fade);
    c.previous();
    expect(c.transition, push);
    expect(c.movedBack, isTrue);
    c.goTo(1);
    expect(c.movedBack, isTrue, reason: 'no step, so nothing changes');
    c.next();
    expect(c.movedBack, isFalse);
    c.dispose();
  });

  test('before loading there is no transition', () {
    final c = controllerFor();
    expect(c.transition, SlideTransitionSpec.none);
    c.dispose();
  });

  testWidgets('the clock counts from the start and the controls idle out', (
    tester,
  ) async {
    final c = controllerFor();
    await c.load();
    expect(c.elapsed.value, Duration.zero);
    expect(c.controlsVisible, isTrue);
    await tester.pump(const Duration(seconds: 2));
    c.wakeControls();
    await tester.pump(const Duration(seconds: 2));
    expect(c.controlsVisible, isTrue, reason: 'woken a moment ago');
    await tester.pump(SlidePresentController.controlsIdle);
    expect(c.controlsVisible, isFalse);
    expect(c.elapsed.value, const Duration(seconds: 7));
    c.wakeControls();
    expect(c.controlsVisible, isTrue);
    c.dispose();
  });

  test('the presenter view toggles', () async {
    final c = controllerFor();
    await c.load();
    expect(c.presenterView, isFalse);
    c.togglePresenterView();
    expect(c.presenterView, isTrue);
    c.dispose();
  });

  test('fullscreen toggles and is left on the way out', () async {
    final screen = FakeFullscreen();
    final c = controllerFor(fullscreen: screen);
    expect(c.canToggleFullscreen, isTrue);
    await c.toggleFullscreen();
    expect(c.isFullscreen, isTrue);
    expect(screen.isActive, isTrue);
    await c.leaveFullscreen();
    expect(screen.isActive, isFalse);
    c.dispose();

    final none = controllerFor(fullscreen: FakeFullscreen(isSupported: false));
    expect(none.canToggleFullscreen, isFalse);
    await none.toggleFullscreen();
    expect(none.isFullscreen, isFalse);
    none.dispose();
  });
}
