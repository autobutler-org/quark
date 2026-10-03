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

  group('week start from a locale (#2539)', () {
    test('maps MaterialLocalizations.firstDayOfWeekIndex to a weekday', () {
      // en-US: Sunday first.
      expect(CalendarDates.firstWeekdayFromIndex(0), DateTime.sunday);
      // de-DE, en-GB: Monday first.
      expect(CalendarDates.firstWeekdayFromIndex(1), DateTime.monday);
      // fa-IR, ar-EG: Saturday first.
      expect(CalendarDates.firstWeekdayFromIndex(6), DateTime.saturday);
    });

    test('falls back to the documented default', () {
      expect(CalendarDates.defaultFirstWeekday, DateTime.sunday);
      expect(
        CalendarDates.firstWeekdayFromIndex(null),
        CalendarDates.defaultFirstWeekday,
      );
      expect(
        CalendarDates.firstWeekdayFromIndex(7),
        CalendarDates.defaultFirstWeekday,
      );
      expect(
        CalendarDates.firstWeekdayFromIndex(-1),
        CalendarDates.defaultFirstWeekday,
      );
    });

    test('monthGrid starts each row on the weekday it is given', () {
      final monday = CalendarDates.monthGrid(
        DateTime(2026, 9),
        firstWeekday: DateTime.monday,
      );
      expect(monday.first, DateTime(2026, 8, 31));
      expect(monday.last, DateTime(2026, 10, 4));

      final saturday = CalendarDates.monthGrid(
        DateTime(2026, 9),
        firstWeekday: DateTime.saturday,
      );
      expect(saturday.first, DateTime(2026, 8, 29));
      expect(saturday.first.weekday, DateTime.saturday);
      expect(saturday.last.weekday, DateTime.friday);
    });
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
