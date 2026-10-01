import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Date arithmetic the calendar widgets and their callers share.
void main() {
  test('key is a zero-padded date', () {
    expect(CalendarDates.key(DateTime(2026, 9, 5, 13, 30)), '2026-09-05');
  });

  test('addDays keeps the time of day and crosses months', () {
    expect(
      CalendarDates.addDays(DateTime(2026, 9, 29, 16, 45), 3),
      DateTime(2026, 10, 2, 16, 45),
    );
    expect(
      CalendarDates.addDays(DateTime(2026, 3, 1), -1),
      DateTime(2026, 2, 28),
    );
  });

  test('addDays across a daylight saving change is one date, not 24 hours', () {
    // Whatever zone the test runs in, each step lands on midnight of the next
    // date; a Duration of 24 hours would drift an hour on a DST day.
    var day = DateTime(2026, 3, 1);
    for (var i = 0; i < 300; i++) {
      final next = CalendarDates.addDays(day, 1);
      expect(next.hour, 0, reason: '${CalendarDates.key(next)} drifted');
      day = next;
    }
  });

  test('startOfWeek honors the first weekday', () {
    final tuesday = DateTime(2026, 9, 29, 9);
    expect(CalendarDates.startOfWeek(tuesday), DateTime(2026, 9, 27));
    expect(
      CalendarDates.startOfWeek(tuesday, firstWeekday: DateTime.monday),
      DateTime(2026, 9, 28),
    );
    expect(CalendarDates.weekOf(tuesday), hasLength(7));
    expect(CalendarDates.weekOf(tuesday).last, DateTime(2026, 10, 3));
  });

  test('monthGrid covers whole weeks around the month', () {
    final september = CalendarDates.monthGrid(DateTime(2026, 9, 17));
    expect(september, hasLength(35));
    expect(september.first, DateTime(2026, 8, 30));
    expect(september.last, DateTime(2026, 10, 3));

    // February 2026 starts on a Sunday and fills four weeks exactly.
    expect(CalendarDates.monthGrid(DateTime(2026, 2)), hasLength(28));

    // August 2026 starts on a Saturday and needs six.
    expect(CalendarDates.monthGrid(DateTime(2026, 8)), hasLength(42));
  });

  test('an item covers every date it touches, its end exclusive', () {
    final weekend = CalendarEventItem(
      eventId: 1,
      title: 'Cabin weekend',
      start: DateTime(2026, 9, 26),
      end: DateTime(2026, 9, 28),
      allDay: true,
    );
    expect(weekend.dates, [DateTime(2026, 9, 26), DateTime(2026, 9, 27)]);

    final lateNight = CalendarEventItem(
      eventId: 2,
      title: 'Late show',
      start: DateTime(2026, 9, 29, 23),
      end: DateTime(2026, 9, 30, 1),
    );
    expect(lateNight.dates, [DateTime(2026, 9, 29), DateTime(2026, 9, 30)]);
    expect(lateNight.key, '2_2026-09-29');
  });

  test('reminderAt counts back from the start', () {
    final vet = CalendarEventItem(
      eventId: 3,
      title: 'Vet',
      start: DateTime(2026, 9, 29, 16),
      end: DateTime(2026, 9, 29, 16, 45),
      reminderMinutes: 30,
    );
    expect(vet.reminderAt, DateTime(2026, 9, 29, 15, 30));

    final rent = CalendarEventItem(
      eventId: 4,
      title: 'Rent',
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 2),
      allDay: true,
      reminderMinutes: 900,
    );
    expect(rent.reminderAt, DateTime(2026, 9, 30, 9));
  });
}
