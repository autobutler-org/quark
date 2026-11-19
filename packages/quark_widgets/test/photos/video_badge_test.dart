import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testWidgets('shows minutes and seconds under an hour', (tester) async {
    await pumpAt(
      tester,
      const VideoBadge(duration: Duration(seconds: 42)),
      size: narrowViewport,
    );

    expect(find.text('0:42'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.play_arrow), findsOneWidget);
  });

  testWidgets('shows hours once a video runs past one', (tester) async {
    await pumpAt(
      tester,
      const VideoBadge(duration: Duration(hours: 1, minutes: 2, seconds: 3)),
      size: narrowViewport,
    );

    expect(find.text('1:02:03'), findsOneWidget);
  });

  testWidgets('is a play glyph alone when the length is unknown', (
    tester,
  ) async {
    await pumpAt(tester, const VideoBadge(), size: narrowViewport);

    expect(find.byIcon(QuarkIcons.play_arrow), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('keeps its scrim and white text in the light theme', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const VideoBadge(duration: Duration(seconds: 5)),
      size: narrowViewport,
      brightness: Brightness.light,
    );

    expect(tester.widget<Text>(find.text('0:05')).style?.color, Colors.white);
  });

  testWidgets('stays small enough for a thumbnail corner', (tester) async {
    await pumpAt(
      tester,
      const Align(
        alignment: Alignment.topLeft,
        child: VideoBadge(duration: Duration(minutes: 3)),
      ),
      size: narrowViewport,
    );

    expect(tester.getSize(find.byType(VideoBadge)).height, lessThan(24));
  });

  test('formats a duration the way a player shows it', () {
    expect(VideoBadge.format(Duration.zero), '0:00');
    expect(VideoBadge.format(const Duration(minutes: 10, seconds: 7)), '10:07');
    expect(
      VideoBadge.format(const Duration(hours: 12, seconds: 9)),
      '12:00:09',
    );
  });
}
