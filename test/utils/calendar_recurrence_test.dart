import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/calendar_event.dart';
import 'package:quark/utils/calendar_recurrence.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Expanding the simple repeat presets into local occurrences (#2491).
CalendarEvent _timed(
  int id,
  DateTime localStart,
  Duration length, {
  CalendarRepeat repeat = CalendarRepeat.none,
}) => CalendarEvent(
  id: id,
  title: 'Event $id',
  start: localStart.toUtc(),
  end: localStart.add(length).toUtc(),
  repeat: repeat,
);

CalendarEvent _allDay(
  int id,
  DateTime date, {
  int days = 1,
  CalendarRepeat repeat = CalendarRepeat.none,
}) => CalendarEvent(
  id: id,
  title: 'All day $id',
  start: DateTime.utc(date.year, date.month, date.day),
  end: DateTime.utc(date.year, date.month, date.day + days),
  allDay: true,
  repeat: repeat,
);

void main() {
  final september = (DateTime(2026, 8, 30), DateTime(2026, 10, 4));

  test('a one-off event shows once, only when it overlaps', () {
    final event = _timed(1, DateTime(2026, 9, 29, 9), const Duration(hours: 1));
    expect(
      expandOccurrences([event], september.$1, september.$2),
      hasLength(1),
    );
    expect(
      expandOccurrences([event], DateTime(2026, 10, 4), DateTime(2026, 10, 11)),
      isEmpty,
    );
  });

  test('weekly lands on the same weekday every week', () {
    // A Monday in August: every Monday of the September grid, and not before
    // its first.
    final trash = _timed(
      2,
      DateTime(2026, 8, 3, 19),
      const Duration(minutes: 15),
      repeat: CalendarRepeat.weekly,
    );
    final items = expandOccurrences([trash], september.$1, september.$2);
    expect(items.map((i) => i.start.day), [31, 7, 14, 21, 28]);
    expect(items.every((i) => i.start.weekday == DateTime.monday), isTrue);
    expect(items.every((i) => i.start.hour == 19), isTrue);
  });

  test('a repeating event keeps its clock time across daylight saving', () {
    // Whatever zone this runs in, 9 AM stays 9 AM for a year of weeks.
    final standup = _timed(
      3,
      DateTime(2026, 1, 5, 9),
      const Duration(minutes: 30),
      repeat: CalendarRepeat.weekly,
    );
    final items = expandOccurrences(
      [standup],
      DateTime(2026, 1, 1),
      DateTime(2027, 1, 1),
    );
    expect(items, hasLength(52));
    expect(
      items.every((i) => i.start.hour == 9 && i.start.minute == 0),
      isTrue,
    );
    expect(
      items.every(
        (i) => i.end.difference(i.start) == const Duration(minutes: 30),
      ),
      isTrue,
    );
  });

  test('daily repeats every date, from the first one on', () {
    final walk = _timed(
      4,
      DateTime(2026, 9, 27, 7),
      const Duration(minutes: 30),
      repeat: CalendarRepeat.daily,
    );
    final items = expandOccurrences([walk], september.$1, september.$2);
    expect(items.first.start, DateTime(2026, 9, 27, 7));
    expect(items, hasLength(7));
  });

  test('monthly skips months without the date', () {
    final bill = _allDay(
      5,
      DateTime(2026, 1, 31),
      repeat: CalendarRepeat.monthly,
    );
    final items = expandOccurrences(
      [bill],
      DateTime(2026, 1, 1),
      DateTime(2026, 8, 1),
    );
    expect(items.map((i) => i.start.month), [1, 3, 5, 7]);
    expect(items.every((i) => i.start.day == 31 && i.allDay), isTrue);
  });

  test('an old series jumps straight to the range', () {
    final daily = _timed(
      6,
      DateTime(2020, 1, 1, 8),
      const Duration(hours: 1),
      repeat: CalendarRepeat.daily,
    );
    final items = expandOccurrences([daily], september.$1, september.$2);
    expect(items, hasLength(35));
    expect(items.first.start, DateTime(2026, 8, 30, 8));
  });

  test('a multi-day occurrence that began before the range still shows', () {
    final weekend = _allDay(
      7,
      DateTime(2026, 8, 29),
      days: 2,
      repeat: CalendarRepeat.weekly,
    );
    final items = expandOccurrences([weekend], september.$1, september.$2);
    expect(items.first.start, DateTime(2026, 8, 29));
    expect(items.first.end, DateTime(2026, 8, 31));
  });

  test('all-day dates stay dates in the local zone', () {
    final rent = _allDay(8, DateTime(2026, 10, 1));
    final item = expandOccurrences([rent], september.$1, september.$2).single;
    expect(item.start, DateTime(2026, 10, 1));
    expect(item.end, DateTime(2026, 10, 2));
    expect(item.key, '8_2026-10-01');
  });

  test('occurrences come back by start', () {
    final items = expandOccurrences(
      [
        _timed(9, DateTime(2026, 9, 29, 16), const Duration(hours: 1)),
        _timed(10, DateTime(2026, 9, 29, 9), const Duration(hours: 1)),
      ],
      september.$1,
      september.$2,
    );
    expect(items.map((i) => i.eventId), [10, 9]);
  });
}
