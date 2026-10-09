import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/widgets/calendar/calendar_body.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// The Calendar body's error states: a failed load after the first one keeps
/// the view on show under a banner with its own Try again (#2540). Also the
/// week start it hands the month grid (#2539) and the empty month and day
/// (#2538), the swipe that steps Day, Week and Month (#2885), and the hours
/// kept in view across a step (#2887).
void main() {
  final today = CalendarDates.dateOnly(DateTime.now());

  Future<int Function()> pumpBody(
    WidgetTester tester,
    Size size, {
    required CalendarView view,
    required bool isInitialLoad,
    String? error,
    bool isLoading = false,
    int firstWeekday = DateTime.sunday,
    List<CalendarEventItem> occurrences = const [],
    VoidCallback? onAddEvent,
    List<String>? log,
    DateTime? from,
  }) async {
    final start = from ?? today;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: CalendarBody(
            view: view,
            anchor: start,
            days: view == CalendarView.day
                ? [start]
                : [for (var i = 0; i < 7; i++) CalendarDates.addDays(start, i)],
            today: today,
            now: DateTime.now(),
            occurrences: occurrences,
            upcoming: const [],
            isInitialLoad: isInitialLoad,
            isLoading: isLoading,
            firstWeekday: firstWeekday,
            error: error,
            onPrevious: () => log?.add('previous'),
            onNext: () => log?.add('next'),
            onRetry: () => retries++,
            onDayTap: (_) {},
            onCreateOn: (_) => log?.add('create'),
            onCreateAt: (_) => log?.add('create'),
            onEventTap: (_) {},
            onAddEvent: onAddEvent ?? () {},
          ),
        ),
      ),
    );
    await tester.pump();
    return () => retries;
  }

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    for (final view in [
      CalendarView.day,
      CalendarView.week,
      CalendarView.month,
    ]) {
      testWidgets('$name ${view.slug}: a later failed load offers Try again', (
        tester,
      ) async {
        final retries = await pumpBody(
          tester,
          size,
          view: view,
          isInitialLoad: false,
          error: "Couldn't load your calendar.",
        );

        expect(
          find.widgetWithText(ErrorBanner, "Couldn't load your calendar."),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('calendar_error_retry')));
        expect(retries(), 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$name upcoming: a failed load offers Try again', (
      tester,
    ) async {
      final retries = await pumpBody(
        tester,
        size,
        view: CalendarView.upcoming,
        isInitialLoad: false,
        error: "Couldn't load your calendar.",
      );

      await tester.tap(find.byKey(const ValueKey('calendar_upcoming_retry')));
      expect(retries(), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: the first failed load keeps its own retry', (
      tester,
    ) async {
      final retries = await pumpBody(
        tester,
        size,
        view: CalendarView.week,
        isInitialLoad: true,
        error: "Couldn't load your calendar.",
      );

      expect(find.byKey(const ValueKey('calendar_error_retry')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('calendar_retry')));
      expect(retries(), 1);
    });

    testWidgets('$name: no banner without an error', (tester) async {
      await pumpBody(
        tester,
        size,
        view: CalendarView.week,
        isInitialLoad: false,
      );

      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.byKey(const ValueKey('calendar_error_retry')), findsNothing);
    });
  }

  // #2603, #2605: every view's controls are labeled, and Upcoming's are 48dp.
  // The day, week and month grids draw slots, day cells and event chips to
  // the calendar's scale, which quark_widgets exempts from the size check
  // until those views are redesigned, so they are held to labels only.
  for (final size in const [narrowViewport, wideViewport]) {
    for (final view in CalendarView.values) {
      testWidgets('${view.slug} is labeled tap targets at $size', (
        tester,
      ) async {
        await pumpBody(
          tester,
          size,
          view: view,
          isInitialLoad: false,
          error: "Couldn't load your calendar.",
        );
        await expectTapTargetGuidelines(
          tester,
          checkSize: view == CalendarView.upcoming,
        );
      });
    }
  }

  for (final size in const [narrowViewport, wideViewport]) {
    testWidgets('month rows start on the week start it is given at $size', (
      tester,
    ) async {
      await pumpBody(
        tester,
        size,
        view: CalendarView.month,
        isInitialLoad: false,
        firstWeekday: DateTime.monday,
      );
      final first = CalendarDates.monthGrid(
        today,
        firstWeekday: DateTime.monday,
      ).first;
      expect(first.weekday, DateTime.monday);
      expect(
        find.byKey(ValueKey('calendar_day_${CalendarDates.key(first)}')),
        findsOneWidget,
      );
      // The Sunday before it would lead a Sunday-first grid.
      expect(
        find.byKey(
          ValueKey(
            'calendar_day_${CalendarDates.key(CalendarDates.addDays(first, -1))}',
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('an empty month says so and offers an event at $size', (
      tester,
    ) async {
      var added = 0;
      await pumpBody(
        tester,
        size,
        view: CalendarView.month,
        isInitialLoad: false,
        onAddEvent: () => added++,
      );
      expect(find.text('Nothing planned this month'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar_month_add')));
      expect(added, 1);
    });

    testWidgets('an empty day says so and offers an event at $size', (
      tester,
    ) async {
      var added = 0;
      await pumpBody(
        tester,
        size,
        view: CalendarView.day,
        isInitialLoad: false,
        onAddEvent: () => added++,
      );
      expect(find.text('Free day'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar_day_add')));
      expect(added, 1);
    });

    testWidgets('a view still loading is not called empty at $size', (
      tester,
    ) async {
      for (final view in [CalendarView.month, CalendarView.day]) {
        await pumpBody(
          tester,
          size,
          view: view,
          isInitialLoad: false,
          isLoading: true,
        );
        expect(find.text('Nothing planned this month'), findsNothing);
        expect(find.text('Free day'), findsNothing);
      }
    });
  }

  // #2885: a swipe steps by how far it went, not only by how fast it was let
  // go, so a mouse drag that comes to rest before the button is released still
  // steps, either way, and never creates an event.
  for (final size in const [narrowViewport, wideViewport]) {
    for (final view in [
      CalendarView.day,
      CalendarView.week,
      CalendarView.month,
    ]) {
      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        testWidgets(
          '${view.slug}: a ${kind.name} drag that stops before release steps '
          'at $size',
          (tester) async {
            final log = <String>[];
            await pumpBody(
              tester,
              size,
              view: view,
              isInitialLoad: false,
              log: log,
            );
            final grid = view == CalendarView.month
                ? find.byType(CalendarMonthGrid)
                : find.byType(CalendarTimeGrid);

            Future<void> drag(double dx) async {
              final gesture = await tester.startGesture(
                tester.getCenter(grid),
                kind: kind,
              );
              for (var i = 0; i < 10; i++) {
                await gesture.moveBy(Offset(dx / 10, 1));
                await tester.pump(const Duration(milliseconds: 16));
              }
              // Held still, so nothing is left of the fling.
              await tester.pump(const Duration(milliseconds: 200));
              await gesture.up();
              await tester.pumpAndSettle();
            }

            await drag(-size.width * 0.3);
            await drag(size.width * 0.3);
            // Too short to mean anything.
            await drag(-20);
            expect(log, ['next', 'previous']);
          },
        );
      }
    }

    testWidgets('week: a drag on the day headings steps at $size', (
      tester,
    ) async {
      final log = <String>[];
      await pumpBody(
        tester,
        size,
        view: CalendarView.week,
        isInitialLoad: false,
        log: log,
      );
      await tester.timedDrag(
        find.byKey(ValueKey('calendar_day_header_${CalendarDates.key(today)}')),
        Offset(-size.width * 0.3, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(log, ['next']);
    });
  }

  // #2887: stepping Day or Week keeps the hours on show. A new span used to be
  // a new timeline, which scrolled back to the morning.
  for (final size in const [narrowViewport, wideViewport]) {
    for (final view in [CalendarView.day, CalendarView.week]) {
      testWidgets('${view.slug}: a step keeps the hours on show at $size', (
        tester,
      ) async {
        Future<void> pumpFrom(DateTime from) => pumpBody(
          tester,
          size,
          view: view,
          isInitialLoad: false,
          from: from,
        );
        final hours = find.descendant(
          of: find.byType(CalendarTimeGrid),
          matching: find.byType(Scrollable),
        );
        double offset() => tester.state<ScrollableState>(hours).position.pixels;

        await pumpFrom(today);
        // From the top of the hours, clear of the empty day's notice.
        await tester.dragFrom(
          tester.getTopLeft(hours) + const Offset(100, 20),
          const Offset(0, 300),
        );
        await tester.pumpAndSettle();
        final early = offset();
        expect(early, lessThan(300));

        await pumpFrom(
          CalendarDates.addDays(today, view == CalendarView.day ? 1 : 7),
        );
        await tester.pumpAndSettle();
        expect(offset(), early);
      });
    }
  }
}
