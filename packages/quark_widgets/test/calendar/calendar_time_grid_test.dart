import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/calendar/calendar_time_grid/time_grid_layout.dart';

import '../support/pump.dart';

/// The hourly timeline behind the Day and Week views.
final _today = DateTime(2026, 9, 29);
final _now = DateTime(2026, 9, 29, 15, 40);

CalendarEventItem _at(int id, String title, int hour, int minute, int length) {
  final start = DateTime(2026, 9, 29, hour, minute);
  return CalendarEventItem(
    eventId: id,
    title: title,
    start: start,
    end: start.add(Duration(minutes: length)),
  );
}

final _call = _at(1, 'Insurance call', 12, 0, 45);
final _lunch = _at(2, 'Lunch with Sam', 12, 30, 60);
final _vet = _at(3, 'Vet', 16, 0, 45);
final _garden = CalendarEventItem(
  eventId: 4,
  title: 'Garden waste pickup',
  start: _today,
  end: DateTime(2026, 9, 30),
  allDay: true,
);

Widget _grid({
  required List<DateTime> days,
  List<CalendarEventItem>? events,
  DateTime? now,
  ValueChanged<DateTime>? onSlotTap,
  ValueChanged<CalendarEventItem>? onEventTap,
  ValueChanged<DateTime>? onDayTap,
}) => CalendarTimeGrid(
  days: days,
  today: _today,
  now: now,
  initialHour: 11,
  events: events ?? [_call, _lunch, _vet, _garden],
  onSlotTap: onSlotTap,
  onEventTap: onEventTap,
  onDayTap: onDayTap,
);

void main() {
  group('layoutDay', () {
    test('splits overlapping events into lanes', () {
      final placed = {
        for (final p in layoutDay(_today, [_vet, _lunch, _call])) p.item: p,
      };
      expect(placed[_call]!.lanes, 2);
      expect(placed[_lunch]!.lanes, 2);
      expect({placed[_call]!.lane, placed[_lunch]!.lane}, {0, 1});
      expect(placed[_vet]!.lanes, 1);
      expect(placed[_vet]!.startMinute, 16 * 60);
      expect(placed[_vet]!.endMinute, 16 * 60 + 45);
    });

    test('clips an event across midnight to each day', () {
      final late = CalendarEventItem(
        eventId: 5,
        title: 'Late show',
        start: DateTime(2026, 9, 29, 23),
        end: DateTime(2026, 9, 30, 1),
      );
      final first = layoutDay(_today, [late]).single;
      expect((first.startMinute, first.endMinute), (23 * 60, 24 * 60));
      final second = layoutDay(DateTime(2026, 9, 30), [late]).single;
      expect((second.startMinute, second.endMinute), (0, 60));
    });

    test('draws a very short event tall enough to tap', () {
      final blip = _at(6, 'Blip', 9, 0, 5);
      final placed = layoutDay(_today, [blip]).single;
      expect(placed.endMinute - placed.startMinute, minimumBlockMinutes);
    });

    test('skips all-day events and other dates', () {
      final tomorrow = CalendarEventItem(
        eventId: 7,
        title: 'Tomorrow',
        start: DateTime(2026, 9, 30, 9),
        end: DateTime(2026, 9, 30, 10),
      );
      expect(layoutDay(_today, [_garden, tomorrow]), isEmpty);
    });
  });

  testBothViewports('a day shows its events and its all-day row', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _grid(days: [_today], now: _now),
      size: size,
    );
    expect(find.text('Garden waste pickup'), findsOneWidget);
    expect(find.text('Insurance call'), findsOneWidget);
    expect(find.text('Lunch with Sam'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar_now_line')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar_day_header_2026-09-29')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('an empty day says it has no all-day events', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _grid(days: [_today], events: const []),
      size: size,
    );
    expect(find.text('No all-day events'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar_now_line')), findsNothing);
  });

  testBothViewports('a week heads each column and taps through to a day', (
    tester,
    size,
  ) async {
    DateTime? opened;
    await pumpAt(
      tester,
      _grid(days: CalendarDates.weekOf(_today), onDayTap: (d) => opened = d),
      size: size,
    );
    for (final day in CalendarDates.weekOf(_today)) {
      expect(
        find.byKey(ValueKey('calendar_day_header_${CalendarDates.key(day)}')),
        findsOneWidget,
      );
    }
    expect(find.text('No all-day events'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('calendar_day_header_2026-10-01')),
    );
    expect(opened, DateTime(2026, 10, 1));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('an empty hour creates at that hour', (tester, size) async {
    DateTime? start;
    await pumpAt(
      tester,
      _grid(days: [_today], events: const [], onSlotTap: (s) => start = s),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_slot_2026-09-29_13')));
    expect(start, DateTime(2026, 9, 29, 13));
  });

  testBothViewports('an event block calls back with its occurrence', (
    tester,
    size,
  ) async {
    CalendarEventItem? tapped;
    await pumpAt(
      tester,
      _grid(days: [_today], onEventTap: (e) => tapped = e),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_event_2_2026-09-29')));
    expect(tapped, _lunch);
  });

  testWidgets('the now line only shows on its own date', (tester) async {
    await pumpAt(
      tester,
      _grid(days: [DateTime(2026, 9, 30)], now: _now),
      size: wideViewport,
    );
    expect(find.byKey(const ValueKey('calendar_now_line')), findsNothing);
  });

  testWidgets('a phone week keeps event titles and drops their times', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _grid(days: CalendarDates.weekOf(_today)),
      size: narrowViewport,
    );
    expect(find.text('Lunch with Sam'), findsOneWidget);
    expect(find.text('12:30 – 1:30 PM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('its slots, events and dates can be pressed by a screen '
      'reader', (tester, size) async {
    await pumpAt(
      tester,
      _grid(
        days: CalendarDates.weekOf(_today),
        onSlotTap: (_) {},
        onEventTap: (_) {},
        onDayTap: (_) {},
      ),
      size: size,
    );

    // Event blocks are as tall as their events last, which #2605 leaves open.
    await expectTapTargetGuidelines(tester, checkSize: false);
  });
}
