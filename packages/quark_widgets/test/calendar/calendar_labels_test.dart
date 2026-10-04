import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The words and times every calendar surface shows.
void main() {
  final morning = DateTime(2026, 9, 29, 9);
  final afternoon = DateTime(2026, 9, 29, 16, 45);

  test('titles', () {
    expect(CalendarLabels.monthTitle(morning), 'September 2026');
    expect(CalendarLabels.monthTitleShort(morning), 'Sep 2026');
    expect(CalendarLabels.dayTitle(morning), 'Tuesday, September 29');
    expect(CalendarLabels.dayTitleShort(morning), 'Tue, Sep 29');
    expect(CalendarLabels.date(morning), 'Tue, Sep 29, 2026');
    expect(
      CalendarLabels.range(DateTime(2026, 9, 27), DateTime(2026, 10, 3)),
      'Sep 27 – Oct 3, 2026',
    );
    expect(
      CalendarLabels.range(
        DateTime(2026, 9, 6),
        DateTime(2026, 9, 12),
        short: true,
      ),
      'Sep 6 – 12',
    );
  });

  test('times in 12- and 24-hour form', () {
    expect(CalendarLabels.time(morning), '9:00 AM');
    expect(CalendarLabels.time(morning, compact: true), '9am');
    expect(CalendarLabels.time(afternoon, compact: true), '4:45pm');
    expect(CalendarLabels.time(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
    expect(CalendarLabels.time(afternoon, use24Hour: true), '16:45');
    expect(CalendarLabels.time(morning, use24Hour: true), '09:00');
    expect(CalendarLabels.hour(12), '12 PM');
    expect(CalendarLabels.hour(0), '12 AM');
    expect(CalendarLabels.hour(7, use24Hour: true), '07:00');
  });

  test('time ranges name AM or PM once when they share it', () {
    expect(
      CalendarLabels.timeRange(DateTime(2026, 9, 29, 16), afternoon),
      '4:00 – 4:45 PM',
    );
    expect(CalendarLabels.timeRange(morning, afternoon), '9:00 AM – 4:45 PM');
    expect(
      CalendarLabels.timeRange(
        DateTime(2026, 9, 29, 23),
        DateTime(2026, 9, 30, 1),
      ),
      '11:00 PM – Wed, Sep 30, 1:00 AM',
    );
  });

  test('repeat presets in plain words', () {
    expect(
      CalendarLabels.repeat(CalendarRepeat.weekly, morning),
      'Every week on Tuesday',
    );
    expect(
      CalendarLabels.repeat(CalendarRepeat.monthly, morning),
      'Every month on the 29th, skipping months without one',
    );
    expect(
      CalendarLabels.repeat(CalendarRepeat.monthly, DateTime(2026, 9, 2)),
      'Every month on the 2nd',
    );
    expect(CalendarLabels.repeat(CalendarRepeat.daily, morning), 'Every day');
    expect(CalendarLabels.repeatShort(CalendarRepeat.none), 'Never');
    expect(
      CalendarLabels.repeatUntil(DateTime(2026, 10, 31)),
      'until Oct 31, 2026',
    );
  });

  test('reminders', () {
    expect(CalendarLabels.reminder(0), 'At start');
    expect(CalendarLabels.reminder(15), '15 min before');
    expect(CalendarLabels.reminder(60), '1 hour before');
    expect(CalendarLabels.reminder(120), '2 hours before');
    expect(CalendarLabels.reminder(1440), '1 day before');
  });

  test('all-day reminders fall at a clock time on a date', () {
    expect(CalendarLabels.reminder(900, allDay: true), 'Day before, 9 AM');
    expect(CalendarLabels.reminder(-540, allDay: true), 'On the day, 9 AM');
    expect(
      CalendarLabels.reminder(900, allDay: true, use24Hour: true),
      'Day before, 09:00',
    );
  });

  test('time until a start', () {
    expect(
      CalendarLabels.startsIn(const Duration(seconds: 20)),
      'Starting now',
    );
    expect(
      CalendarLabels.startsIn(const Duration(minutes: 20)),
      'Starts in 20 min',
    );
    expect(
      CalendarLabels.startsIn(const Duration(minutes: 65)),
      'Starts in 1 h 5 min',
    );
    expect(CalendarLabels.startsIn(const Duration(hours: 2)), 'Starts in 2 h');
  });
}
