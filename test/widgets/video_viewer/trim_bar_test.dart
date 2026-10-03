import 'package:flutter/material.dart';
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
}
