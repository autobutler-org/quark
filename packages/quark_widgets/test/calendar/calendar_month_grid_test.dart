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
}) => CalendarMonthGrid(
  month: month ?? DateTime(2026, 9),
  today: _today,
  selectedDay: _today,
  events: events ?? [_weekend, ..._busyDay],
  onDayTap: onDayTap,
  onDayLongPress: onDayLongPress,
  onAddTap: onAddTap,
  onEventTap: onEventTap,
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

  testBothViewports('lists a multi-day event on each date', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _grid(events: [_weekend]), size: size);
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

  testBothViewports('taps, long presses and event taps call back', (
    tester,
    size,
  ) async {
    DateTime? tapped;
    DateTime? pressed;
    CalendarEventItem? event;
    await pumpAt(
      tester,
      _grid(
        events: [_weekend],
        onDayTap: (d) => tapped = d,
        onDayLongPress: (d) => pressed = d,
        onEventTap: (e) => event = e,
      ),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_day_2026-09-15')));
    expect(tapped, DateTime(2026, 9, 15));
    await tester.longPress(
      find.byKey(const ValueKey('calendar_day_2026-09-16')),
    );
    expect(pressed, DateTime(2026, 9, 16));
    await tester.tap(
      find.byKey(const ValueKey('calendar_event_1_2026-09-26')).first,
    );
    expect(event, _weekend);
  });

  testWidgets('goes dense on a phone: no times, narrow weekday names', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _grid(events: [_timed(3, 'Dentist', 22, 9)]),
      size: narrowViewport,
    );
    expect(find.text('Dentist'), findsOneWidget);
    expect(find.text('9am'), findsNothing);
    expect(find.text('SUN'), findsNothing);
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
}
