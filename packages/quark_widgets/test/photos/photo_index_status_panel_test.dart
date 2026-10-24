import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The photo library index status above duplicate results (#3556): whether
/// results may be incomplete, the counts, pause and resume for an admin, and
/// the files that could not be read.
void main() {
  const failures = [
    PhotoIndexFailureItem(
      id: ':a/broken.jpg',
      name: 'broken.jpg',
      location: 'Photos',
      reason: "Can't be read as a photo",
    ),
    PhotoIndexFailureItem(
      id: 'usb:IMG_1.CR2',
      name: 'IMG_1.CR2',
      location: 'USB drive',
      reason: 'Needs a RAW converter',
    ),
  ];

  Future<void> pumpPanel(
    WidgetTester tester, {
    Size size = wideViewport,
    int total = 5000,
    int hashed = 1200,
    int datesRead = 1100,
    int failed = 0,
    bool isRunning = true,
    bool isPaused = false,
    DateTime? lastRunAt,
    List<PhotoIndexFailureItem> failureItems = const [],
    bool showFailures = false,
    bool isLoading = false,
    bool isChanging = false,
    String? error,
    List<String>? events,
    bool admin = true,
  }) => pumpAt(
    tester,
    Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: PhotoIndexStatusPanel(
          total: total,
          hashed: hashed,
          datesRead: datesRead,
          failed: failed,
          isRunning: isRunning,
          isPaused: isPaused,
          lastRunAt: lastRunAt,
          failures: failureItems,
          showFailures: showFailures,
          isLoading: isLoading,
          isChanging: isChanging,
          error: error,
          onPause: admin ? () => events?.add('pause') : null,
          onResume: admin ? () => events?.add('resume') : null,
          onToggleFailures: () => events?.add('toggle'),
        ),
      ),
    ),
    size: size,
  );

  testBothViewports('says a running pass may leave results incomplete', (
    tester,
    size,
  ) async {
    await pumpPanel(tester, size: size, failed: 2, failureItems: failures);

    expect(
      find.text('Still indexing, so results may be incomplete'),
      findsOneWidget,
    );
    expect(find.textContaining('1200 of 5000 photos'), findsOneWidget);
    expect(find.textContaining('1100 dates read'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_index_pause')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('photo_index_failures_toggle')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
  });

  testBothViewports('lists every failure with its reason when shown', (
    tester,
    size,
  ) async {
    await pumpPanel(
      tester,
      size: size,
      failed: 7,
      failureItems: failures,
      showFailures: true,
    );

    expect(
      find.byKey(const ValueKey('photo_index_failure_:a/broken.jpg')),
      findsOneWidget,
    );
    expect(find.text('broken.jpg'), findsOneWidget);
    expect(find.textContaining("Can't be read as a photo"), findsOneWidget);
    expect(find.textContaining('Needs a RAW converter'), findsOneWidget);
    // Seven failed, two listed: the panel says the list is cut short.
    expect(find.text('Showing the first 2 of 7.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pause, resume and the failure toggle call out', (tester) async {
    final events = <String>[];
    await pumpPanel(tester, failed: 2, failureItems: failures, events: events);
    await tester.tap(find.byKey(const ValueKey('photo_index_pause')));
    await tester.tap(find.byKey(const ValueKey('photo_index_failures_toggle')));

    await pumpPanel(tester, isPaused: true, events: events);
    expect(
      find.text('Indexing paused, so results may be incomplete'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('photo_index_pause')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('photo_index_resume')));

    expect(events, ['pause', 'toggle', 'resume']);
  });

  testWidgets('a change in flight disables the control', (tester) async {
    final events = <String>[];
    await pumpPanel(tester, isChanging: true, events: events);
    await tester.tap(find.byKey(const ValueKey('photo_index_pause')));
    expect(events, isEmpty);
  });

  testWidgets('without callbacks there is no control, only the note', (
    tester,
  ) async {
    await pumpPanel(tester, admin: false);

    expect(
      find.text('Still indexing, so results may be incomplete'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('photo_index_pause')), findsNothing);
    expect(find.byKey(const ValueKey('photo_index_resume')), findsNothing);
  });

  testWidgets('a complete index says so', (tester) async {
    await pumpPanel(
      tester,
      hashed: 5000,
      datesRead: 5000,
      isRunning: false,
      lastRunAt: DateTime(2026, 10, 20, 9, 30),
    );

    expect(find.text('All 5000 photos indexed'), findsOneWidget);
    expect(find.textContaining('may be incomplete'), findsNothing);
    expect(find.byKey(const ValueKey('photo_index_pause')), findsNothing);
    expect(find.textContaining('Last finished'), findsOneWidget);
  });

  testWidgets('an idle index short of the library is still incomplete', (
    tester,
  ) async {
    await pumpPanel(tester, isRunning: false);

    expect(
      find.text('Not every photo is indexed, so results may be incomplete'),
      findsOneWidget,
    );
  });

  testBothViewports('shows loading and the error it is given', (
    tester,
    size,
  ) async {
    await pumpPanel(tester, size: size, isLoading: true);
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.textContaining('may be incomplete'), findsNothing);

    await pumpPanel(
      tester,
      size: size,
      error: "Couldn't load the photo index status.",
    );
    expect(find.text("Couldn't load the photo index status."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testLargeText('survives large text', (tester, size) async {
    await pumpPanel(
      tester,
      size: size,
      failed: 2,
      failureItems: failures,
      showFailures: true,
    );
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });
}
