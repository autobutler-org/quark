import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/present/slide_present_stage.dart';
import 'package:quark/widgets/slides/present/slide_presenter_view.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// A presentation is shown in its theme (#1163), on the stage and in the
/// presenter view's next-slide preview; a swipe steps on how far it went as
/// well as how fast (#2936).
void main() {
  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('draws the slides in the deck\'s theme ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Scaffold(
            body: SlidePresenterView(
              stage: SlidePresentStage(
                slide: Slide(id: 's1'),
                size: SlideSize.widescreen,
                label: 'Slide 1 of 2',
                theme: SlideThemes.dark,
              ),
              next: Slide(id: 's2'),
              size: SlideSize.widescreen,
              notes: '',
              elapsed: ValueNotifier(Duration.zero),
              theme: SlideThemes.dark,
            ),
          ),
        ),
      );
      final canvases = tester.widgetList<SlideCanvas>(find.byType(SlideCanvas));
      expect(canvases, hasLength(2));
      expect(canvases.map((c) => c.theme), everyElement(SlideThemes.dark));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      group('a ${kind.name} swipe ($name)', () {
        late List<String> log;

        Future<void> pumpStage(WidgetTester tester) async {
          log = [];
          tap.setViewport(tester, size);
          await tester.pumpWidget(
            MaterialApp(
              theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
              home: Scaffold(
                body: SlidePresentStage(
                  slide: Slide(id: 's1'),
                  size: SlideSize.widescreen,
                  label: 'Slide 2 of 3',
                  onNext: () => log.add('next'),
                  onPrevious: () => log.add('previous'),
                ),
              ),
            ),
          );
        }

        /// Drags [dx] across the stage in ten even moves, [frame] apart,
        /// then holds still for [hold] before letting go.
        Future<void> drag(
          WidgetTester tester,
          double dx, {
          Duration frame = const Duration(milliseconds: 16),
          Duration hold = Duration.zero,
        }) async {
          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(SlidePresentStage)),
            kind: kind,
          );
          // Stamped, or every move lands at once and no speed is measured.
          var at = Duration.zero;
          for (var i = 0; i < 10; i++) {
            at += frame;
            await gesture.moveBy(Offset(dx / 10, 0), timeStamp: at);
            await tester.pump(frame);
          }
          await tester.pump(hold);
          await gesture.up(timeStamp: at + hold);
          await tester.pumpAndSettle();
        }

        // Held still before release, so nothing is left of the fling.
        const hold = Duration(milliseconds: 200);

        testWidgets('a slow, long drag steps', (tester) async {
          await pumpStage(tester);
          await drag(tester, -size.width * 0.4, hold: hold);
          await drag(tester, size.width * 0.4, hold: hold);
          expect(log, ['next', 'previous']);
          expect(tester.takeException(), isNull);
        });

        testWidgets('a short, fast flick steps once', (tester) async {
          await pumpStage(tester);
          const frame = Duration(milliseconds: 4);
          await drag(tester, -40, frame: frame);
          await drag(tester, 40, frame: frame);
          expect(log, ['next', 'previous']);
        });

        testWidgets('a tiny, slow drag steps nowhere', (tester) async {
          await pumpStage(tester);
          const frame = Duration(milliseconds: 40);
          await drag(tester, -30, frame: frame, hold: hold);
          await drag(tester, 30, frame: frame, hold: hold);
          expect(log, isEmpty);
        });
      });
    }
  }
}
