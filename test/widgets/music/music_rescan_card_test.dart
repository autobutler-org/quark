import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/job.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/music/music_rescan_card.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// The admin's Rescan music library action in Settings (#3283).
void main() {
  Future<void> pump(WidgetTester tester, Future<Job> Function() rescan) =>
      tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Scaffold(
            body: SingleChildScrollView(child: MusicRescanCard(rescan: rescan)),
          ),
        ),
      );

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('queues a rescan and says where it shows ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      var calls = 0;
      await pump(tester, () async {
        calls++;
        return Job(
          id: 1,
          kind: 'music_rescan',
          name: '',
          status: JobStatus.pending,
          createdAt: DateTime.utc(2026),
        );
      });
      await tester.tap(find.byKey(const ValueKey('settings_music_rescan')));
      await tester.pump();

      expect(calls, 1);
      expect(
        find.byKey(const ValueKey('settings_music_rescan_queued')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('a refusal is worded by Errors, not shown raw', (tester) async {
    await pump(tester, () async => throw ApiException(403, 'rescan music'));
    await tester.tap(find.byKey(const ValueKey('settings_music_rescan')));
    await tester.pump();

    final error = tester.widget<Text>(
      find.byKey(const ValueKey('settings_music_rescan_error')),
    );
    expect(
      error.data,
      Errors.message(ApiException(403, ''), 'start a music scan'),
    );
    expect(error.data, isNot(contains('ApiException')));
    expect(
      find.byKey(const ValueKey('settings_music_rescan_queued')),
      findsNothing,
    );
  });
}
