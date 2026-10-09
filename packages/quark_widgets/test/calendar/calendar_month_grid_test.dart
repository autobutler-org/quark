import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The month grid: its weeks, today, events on the dates they span, overflow,
/// and every callback.
final _today = DateTime(2026, 9, 29);

CalendarEventItem _timed(int id, String title, int day, int hour) =>
    CalendarEventItem(
      eventId: id,
      title: title,
      start: DateTime(2026, 9, day, hour),
      end: DateTime(2026, 9, day, hour + 1),
    );

final _weekend = CalendarEventItem(
  eventId: 1,
  title: 'Cabin weekend',
  start: DateTime(2026, 9, 26),
  end: DateTime(2026, 9, 28),
  allDay: true,
);

final _busyDay = [
  for (var i = 0; i < 6; i++) _timed(10 + i, 'Thing $i', 29, 8 + i),
];

Widget _grid({
  List<CalendarEventItem>? events,
  DateTime? month,
  ValueChanged<DateTime>? onDayTap,
  ValueChanged<DateTime>? onDayLongPress,
  ValueChanged<DateTime>? onAddTap,
  ValueChanged<CalendarEventItem>? onEventTap,
  VoidCallback? onAddEvent,
  bool isLoading = false,
  int firstWeekday = DateTime.sunday,
}) => CalendarMonthGrid(
  month: month ?? DateTime(2026, 9),
  today: _today,
  selectedDay: _today,
  events: events ?? [_weekend, ..._busyDay],
  firstWeekday: firstWeekday,
  isLoading: isLoading,
  onDayTap: onDayTap,
  onDayLongPress: onDayLongPress,
  onAddTap: onAddTap,
  onEventTap: onEventTap,
  onAddEvent: onAddEvent,
);

/// [child] with its text scaled by [factor], as a large-text setting does.
Widget _scaled(Widget child, double factor) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(factor)),
    child: child,
  ),
);

void main() {
  testBothViewports('lays out the weeks around the month', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _grid(events: const []), size: size);
    expect(
      find.byKey(const ValueKey('calendar_day_2026-08-30')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar_day_2026-10-03')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calendar_day_2026-10-04')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('marks today with the accent', (tester, size) async {
    await pumpAt(tester, _grid(events: const []), size: size);
    final number = find.descendant(
      of: find.byKey(const ValueKey('calendar_day_2026-09-29')),
      matching: find.text('29'),
    );
    final marker = tester.widget<Container>(
      find.ancestor(of: number, matching: find.byType(Container)).first,
    );
    expect(
      (marker.decoration! as BoxDecoration).color,
      QuarkTokens.dark.primary,
    );
  });

  testWidgets('lists a multi-day event on each date on a desktop', (
    tester,
  ) async {
    await pumpAt(tester, _grid(events: [_weekend]), size: wideViewport);
    expect(find.text('Cabin weekend'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('calendar_event_1_2026-09-26')),
      findsNWidgets(2),
    );
  });

  testBothViewports('sends a crowded date to its overflow line', (
    tester,
    size,
  ) async {
    DateTime? tapped;
    await pumpAt(tester, _grid(onDayTap: (d) => tapped = d), size: size);
    final more = find.byKey(const ValueKey('calendar_more_2026-09-29'));
    expect(more, findsOneWidget);
    await tester.tap(more);
    expect(tapped, DateTime(2026, 9, 29));
  });

  testBothViewports('taps and long presses call back', (tester, size) async {
    DateTime? tapped;
    DateTime? pressed;
    await pumpAt(
      tester,
      _grid(
        events: [_weekend],
        onDayTap: (d) => tapped = d,
        onDayLongPress: (d) => pressed = d,
      ),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_day_2026-09-15')));
    expect(tapped, DateTime(2026, 9, 15));
    await tester.longPress(
      find.byKey(const ValueKey('calendar_day_2026-09-16')),
    );
    expect(pressed, DateTime(2026, 9, 16));
  });

  testWidgets('an event chip calls back on a desktop', (tester) async {
    CalendarEventItem? event;
    await pumpAt(
      tester,
      _grid(events: [_weekend], onEventTap: (e) => event = e),
      size: wideViewport,
    );
    await tester.tap(
      find.byKey(const ValueKey('calendar_event_1_2026-09-26')).first,
    );
    expect(event, _weekend);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('on a touch platform a tap on an event chip opens its date '
      '(#2939)', (tester) async {
    final opened = <DateTime>[];
    final events = <CalendarEventItem>[];
    await pumpAt(
      tester,
      _grid(events: [_weekend], onDayTap: opened.add, onEventTap: events.add),
      size: wideViewport,
    );
    await tester.tap(
      find.byKey(const ValueKey('calendar_event_1_2026-09-26')).first,
    );
    expect(opened, [DateTime(2026, 9, 26)]);
    expect(events, isEmpty);
  });

  testWidgets('on a touch platform a chip keeps its tap when the date has '
      'none to take it', (tester) async {
    final events = <CalendarEventItem>[];
    await pumpAt(
      tester,
      _grid(events: [_weekend], onEventTap: events.add),
      size: wideViewport,
    );
    await tester.tap(
      find.byKey(const ValueKey('calendar_event_1_2026-09-26')).first,
    );
    expect(events, [_weekend]);
  });

  testWidgets('goes dense on a phone: no times, narrow weekday names', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _grid(events: [_timed(3, 'Dentist', 22, 9)]),
      size: narrowViewport,
    );
    expect(find.text('9am'), findsNothing);
    expect(find.text('SUN'), findsNothing);
  });

  group('a phone marks events instead of truncating them (#2541)', () {
    testWidgets('a date shows a dot per event, not a clipped title', (
      tester,
    ) async {
      await pumpAt(
        tester,
        _grid(
          events: [
            _timed(3, 'Dentist appointment', 22, 9),
            _timed(4, 'Parent teacher night', 22, 18),
          ],
        ),
        size: narrowViewport,
      );
      expect(find.text('Dentist appointment'), findsNothing);
      expect(
        find.byKey(const ValueKey('calendar_event_3_2026-09-22')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar_dots_2026-09-22')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('calendar_dots_2026-09-22')),
          matching: find.byKey(const ValueKey('calendar_dot_3_2026-09-22')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar_dots_2026-09-23')),
        findsNothing,
      );
    });

    testWidgets('a crowded date caps its dots and counts the rest', (
      tester,
    ) async {
      await pumpAt(tester, _grid(), size: narrowViewport);
      final dots = find.descendant(
        of: find.byKey(const ValueKey('calendar_dots_2026-09-29')),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('calendar_dot_'),
        ),
      );
      expect(dots, findsNWidgets(CalendarMonthGrid.maxDots));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('calendar_more_2026-09-29')),
          matching: find.text('+${6 - CalendarMonthGrid.maxDots}'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a screen reader hears every title on the date', (
      tester,
    ) async {
      await pumpAt(
        tester,
        _grid(
          events: [_timed(3, 'Dentist', 22, 9), _timed(4, 'Piano', 22, 16)],
        ),
        size: narrowViewport,
      );
      final handle = tester.ensureSemantics();
      final day = tester.getSemantics(
        find.byKey(const ValueKey('calendar_day_2026-09-22')),
      );
      expect(
        day.label,
        startsWith('Tuesday, September 22, 2 events: Dentist, Piano'),
      );
      handle.dispose();
    });

    testWidgets('tapping a marked date opens it', (tester) async {
      DateTime? tapped;
      await pumpAt(
        tester,
        _grid(onDayTap: (d) => tapped = d),
        size: narrowViewport,
      );
      await tester.tap(find.byKey(const ValueKey('calendar_dots_2026-09-29')));
      expect(tapped, DateTime(2026, 9, 29));
    });
  });

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets('survives text at twice the size at $size', (tester) async {
      await pumpAt(tester, _scaled(_grid(), 2), size: size);
      expect(tester.takeException(), isNull);
      await pumpAt(
        tester,
        _scaled(_grid(events: const [], onAddEvent: () {}), 2),
        size: size,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Nothing planned this month'), findsOneWidget);
    });
  }

  group('week start (#2539)', () {
    testBothViewports('rows start on the weekday given', (tester, size) async {
      await pumpAt(
        tester,
        _grid(events: const [], firstWeekday: DateTime.monday),
        size: size,
      );
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('calendar_day_2026-08-31')),
      );
      final sunday = tester.getTopLeft(
        find.byKey(const ValueKey('calendar_day_2026-09-06')),
      );
      expect(first.dy, sunday.dy);
      expect(first.dx, lessThan(sunday.dx));
      expect(
        find.byKey(const ValueKey('calendar_day_2026-08-30')),
        findsNothing,
      );
    });

    testWidgets('the weekday row follows it', (tester) async {
      await pumpAt(
        tester,
        _grid(events: const [], firstWeekday: DateTime.saturday),
        size: wideViewport,
      );
      final sat = tester.getTopLeft(find.text('SAT'));
      final sun = tester.getTopLeft(find.text('SUN'));
      final fri = tester.getTopLeft(find.text('FRI'));
      expect(sat.dx, lessThan(sun.dx));
      expect(sun.dx, lessThan(fri.dx));
    });
  });

  group('an empty month (#2538)', () {
    testBothViewports('keeps the grid and offers to add an event', (
      tester,
      size,
    ) async {
      var added = 0;
      await pumpAt(
        tester,
        _grid(events: const [], onAddEvent: () => added++),
        size: size,
      );
      expect(
        find.byKey(const ValueKey('calendar_day_2026-09-15')),
        findsOneWidget,
      );
      expect(find.text('Nothing planned this month'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar_month_add')));
      expect(added, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an event on a padding date still leaves the month empty', (
      tester,
    ) async {
      await pumpAt(
        tester,
        _grid(
          events: [
            CalendarEventItem(
              eventId: 8,
              title: 'Late August',
              start: DateTime(2026, 8, 31, 9),
              end: DateTime(2026, 8, 31, 10),
            ),
          ],
          onAddEvent: () {},
        ),
      );
      expect(find.text('Nothing planned this month'), findsOneWidget);
    });

    testWidgets('says nothing while the month loads or has events', (
      tester,
    ) async {
      await pumpAt(
        tester,
        _grid(events: const [], isLoading: true, onAddEvent: () {}),
      );
      expect(find.text('Nothing planned this month'), findsNothing);
      await pumpAt(tester, _grid(onAddEvent: () {}));
      expect(find.text('Nothing planned this month'), findsNothing);
    });

    testBothViewports('its button is a labeled, full-size target', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        Padding(
          padding: const EdgeInsets.all(8),
          child: _grid(events: const [], onAddEvent: () {}),
        ),
        size: size,
      );
      await expectTapTargetGuidelines(tester);
    });
  });

  testWidgets('shows times and full weekday names on a desktop', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _grid(events: [_timed(3, 'Dentist', 22, 9)]),
      size: wideViewport,
    );
    expect(find.text('9am'), findsOneWidget);
    expect(find.text('SUN'), findsOneWidget);
  });

  testWidgets('hovering a date on desktop offers an add button', (
    tester,
  ) async {
    DateTime? added;
    await pumpAt(
      tester,
      _grid(events: const [], onAddTap: (d) => added = d),
      size: wideViewport,
    );
    final add = find.byKey(const ValueKey('calendar_add_2026-09-17'));
    expect(add, findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('calendar_day_2026-09-17'))),
    );
    await tester.pump();
    expect(add, findsOneWidget);
    await tester.tap(add);
    expect(added, DateTime(2026, 9, 17));
  });

  testWidgets('a six-week month still fits a phone', (tester) async {
    await pumpAt(
      tester,
      _grid(month: DateTime(2026, 8), events: const []),
      size: narrowViewport,
    );
    expect(
      find.byKey(const ValueKey('calendar_day_2026-09-05')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('every date can be pressed by a screen reader, and is a '
      '48dp target', (tester, size) async {
    final tapped = <DateTime>[];
    await pumpAt(
      tester,
      _grid(onDayTap: tapped.add, onEventTap: (_) {}),
      size: size,
    );
    final handle = tester.ensureSemantics();

    final day = tester.getSemantics(
      find.byKey(const ValueKey('calendar_day_2026-09-29')),
    );
    day.owner!.performAction(day.id, SemanticsAction.tap);
    expect(tapped, [DateTime(2026, 9, 29)]);
    handle.dispose();
    // The cell is the one target at both sizes: a phone cell holds dots
    // (#2541), and a wide one's chips hand their tap to it on a touch
    // platform (#2939).
    await expectTapTargetGuidelines(tester);
  });
}
