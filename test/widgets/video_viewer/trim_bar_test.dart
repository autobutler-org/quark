import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/video_viewer/trim_bar.dart';

import '../../support/text_scale.dart';

/// #2606: the trim bar's timestamps sit in a slot above each handle. The slot
/// was a fixed 14 pixels of 10 point text, which cut the timestamps off at
/// large text sizes.
void main() {
  Future<void> pumpBar(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: TrimBar(
            start: 0.2,
            end: 0.8,
            duration: const Duration(minutes: 3, seconds: 25),
            onStartChanged: (_) {},
            onEndChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  testWidgets('never sets its timestamps smaller than 11', (tester) async {
    await pumpBar(tester);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize, greaterThanOrEqualTo(11));
    }
  });

  testLargeText('fits its timestamps', (tester, _) async {
    await pumpBar(tester);

    expect(find.text('00:41.0'), findsOneWidget);
    expect(find.text('02:44.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  testLargeText('keeps each handle centered on the track', (tester, _) async {
    await pumpBar(tester);

    final track = tester.getRect(find.byType(Container).first);
    for (final handle in find.byType(GestureDetector).evaluate()) {
      final rect = tester.getRect(find.byWidget(handle.widget));
      expect(rect.center.dy, moreOrLessEquals(track.center.dy, epsilon: 0.5));
    }
  });

  group('#3431: playhead and handles at phone width', () {
    Future<List<double>> pumpPhone(
      WidgetTester tester, {
      required double start,
      required double end,
      required double position,
    }) async {
      tester.view.physicalSize = const Size(412, 924);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final changes = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TrimBar(
                start: start,
                end: end,
                position: position,
                duration: const Duration(seconds: 6),
                onStartChanged: changes.add,
                onEndChanged: (v) => changes.add(-v),
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    const startHandle = ValueKey('trim_bar_start_handle');
    const endHandle = ValueKey('trim_bar_end_handle');
    const playhead = ValueKey('trim_bar_playhead');

    testWidgets('a playhead on the start handle neither hides nor blocks it', (
      tester,
    ) async {
      final changes = await pumpPhone(
        tester,
        start: 0.3,
        end: 0.6,
        position: 0.3,
      );

      final handle = tester.getRect(find.byKey(startHandle));
      final line = tester.getRect(find.byKey(playhead));
      // A thin line, not a second circle the size of the handle.
      expect(line.width, lessThan(handle.width / 4));
      expect(line.center.dx, moreOrLessEquals(handle.center.dx, epsilon: 1));
      // The handle paints over the line and owns the touch.
      final hit = tester.hitTestOnBinding(handle.center);
      expect(
        hit.path.any(
          (e) => e.target == tester.renderObject(find.byKey(startHandle)),
        ),
        isTrue,
      );
      await tester.drag(find.byKey(startHandle), const Offset(-40, 0));
      expect(changes, isNotEmpty);
      expect(changes.every((v) => v >= 0), isTrue);
    });

    testWidgets('both handles have a full touch target', (tester) async {
      await pumpPhone(tester, start: 0.3, end: 0.6, position: 0.3);

      for (final key in [startHandle, endHandle]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
        expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      }
    });

    testWidgets('the end handle stops a handle width short of the start', (
      tester,
    ) async {
      final changes = await pumpPhone(
        tester,
        start: 0.3,
        end: 0.6,
        position: 0.3,
      );

      await tester.drag(find.byKey(endHandle), const Offset(-400, 0));
      final barWidth = 412 - 16.0;
      final closest = -changes.reduce((a, b) => a > b ? a : b);
      expect((closest - 0.3) * barWidth, greaterThanOrEqualTo(24 - 0.5));
    });
  });
}
