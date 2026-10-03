import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('reads LIVE', (tester, size) async {
    await pumpAt(tester, const LiveBadge(), size: size);

    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('keeps its scrim and white text in the light theme', (
    tester,
  ) async {
    // It is drawn on a photograph, not on a surface, so following the theme
    // into light mode would make it disappear against a bright picture.
    await pumpAt(
      tester,
      const LiveBadge(),
      size: narrowViewport,
      brightness: Brightness.light,
    );

    final text = tester.widget<Text>(find.text('LIVE'));
    expect(text.style?.color, Colors.white);

    final container = tester.widget<Container>(find.byType(Container));
    expect((container.decoration! as BoxDecoration).color, Colors.black54);
  });

  testWidgets('stays small enough for a thumbnail corner', (tester) async {
    await pumpAt(
      tester,
      const Align(alignment: Alignment.topLeft, child: LiveBadge()),
      size: narrowViewport,
    );

    expect(tester.getSize(find.byType(LiveBadge)).height, lessThan(24));
  });

  testBothViewports('shows a dot in the viewer form', (tester, size) async {
    await pumpAt(tester, const LiveBadge(ready: true), size: size);

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.circle), findsOneWidget);
  });

  testWidgets('dims the dot and the text while the live video loads', (
    tester,
  ) async {
    await pumpAt(tester, const LiveBadge(ready: false), size: narrowViewport);

    expect(
      tester.widget<Icon>(find.byIcon(QuarkIcons.circle)).color,
      Colors.white38,
    );
    expect(tester.widget<Text>(find.text('LIVE')).style?.color, Colors.white54);
  });

  testWidgets('lights the dot and the text once the video can play', (
    tester,
  ) async {
    await pumpAt(tester, const LiveBadge(ready: true), size: narrowViewport);

    expect(
      tester.widget<Icon>(find.byIcon(QuarkIcons.circle)).color,
      Colors.yellowAccent,
    );
    expect(tester.widget<Text>(find.text('LIVE')).style?.color, Colors.white);
  });

  testWidgets('draws no dot on a thumbnail', (tester) async {
    await pumpAt(tester, const LiveBadge(), size: narrowViewport);

    expect(find.byIcon(QuarkIcons.circle), findsNothing);
  });

  // #2606: no text in the badge starts below 11 points.
  testBothViewports('never sets type smaller than 11', (tester, size) async {
    for (final ready in [null, false, true]) {
      await pumpAt(tester, LiveBadge(ready: ready), size: size);

      final style = tester.widget<Text>(find.text('LIVE')).style!;
      expect(style.fontSize, greaterThanOrEqualTo(11));
    }
  });

  testLargeText('fits its text', (tester, size) async {
    await pumpAt(
      tester,
      const Column(children: [LiveBadge(), LiveBadge(ready: true)]),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });
}
