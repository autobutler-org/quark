import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/rescan_music_section.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// The admin's "Rescan music library" card (#3283): it queues the scan once
/// per press and says whether the Quark took it.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Future<void> Function() rescan, {
    Size size = tap.narrowViewport,
  }) async {
    tap.setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RescanMusicSection(rescan: rescan),
          ),
        ),
      ),
    );
  }

  const button = ValueKey('rescan_music_button');
  const status = ValueKey('rescan_music_status');

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('queues a scan and says so ($name)', (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await pump(tester, () {
        calls++;
        return pending.future;
      }, size: size);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(find.byKey(button));
      await tester.pump();
      // Busy while the Quark answers, so a second press sends nothing.
      await tester.tap(find.byKey(button));
      await tester.pump();
      expect(calls, 1);

      pending.complete();
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(status)).data,
        'Scan queued. Its progress shows in Jobs.',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a refusal reads through Errors', (tester) async {
    await pump(tester, () async => throw ApiException(403, 'rescan music'));

    await tester.tap(find.byKey(button));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(status)).data,
      "You don't have permission to rescan the music library.",
    );
  });
}
