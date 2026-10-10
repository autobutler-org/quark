import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// An all-day reminder's minutes, to and from a date and a time of day.
void main() {
  test('the 9 AM presets keep their stored values', () {
    expect(
      CalendarReminders.allDayMinutes(
        daysBefore: 1,
        minuteOfDay: CalendarReminders.defaultAllDayMinuteOfDay,
      ),
      900,
    );
    expect(
      CalendarReminders.allDayMinutes(
        daysBefore: 0,
        minuteOfDay: CalendarReminders.defaultAllDayMinuteOfDay,
      ),
      -540,
    );
  });

  test('decodes a stored value into its date and time of day', () {
    expect(CalendarReminders.allDayDaysBefore(900), 1);
    expect(CalendarReminders.allDayMinuteOfDay(900), 540);
    expect(CalendarReminders.allDayDaysBefore(-540), 0);
    expect(CalendarReminders.allDayMinuteOfDay(-540), 540);
    // Midnight belongs to the date it starts: 0 is the day itself, 1440 the
    // day before.
    expect(CalendarReminders.allDayDaysBefore(0), 0);
    expect(CalendarReminders.allDayMinuteOfDay(0), 0);
    expect(CalendarReminders.allDayDaysBefore(1440), 1);
    expect(CalendarReminders.allDayMinuteOfDay(1440), 0);
    // 11:59 PM on the day, the lowest value stored.
    expect(CalendarReminders.allDayDaysBefore(-1439), 0);
    expect(CalendarReminders.allDayMinuteOfDay(-1439), 1439);
  });

  test('every stored value round-trips', () {
    for (
      var minutes = CalendarReminders.minAllDayMinutes;
      minutes <= CalendarReminders.maxAllDayMinutes;
      minutes++
    ) {
      final minuteOfDay = CalendarReminders.allDayMinuteOfDay(minutes);
      expect(minuteOfDay, inInclusiveRange(0, 1439));
      expect(
        CalendarReminders.allDayMinutes(
          daysBefore: CalendarReminders.allDayDaysBefore(minutes),
          minuteOfDay: minuteOfDay,
        ),
        minutes,
      );
    }
  });

  test('any time on the day or the day before is a value the Quark takes', () {
    for (final daysBefore in [0, 1]) {
      for (var minuteOfDay = 0; minuteOfDay < 24 * 60; minuteOfDay++) {
        expect(
          CalendarReminders.allDayMinutes(
            daysBefore: daysBefore,
            minuteOfDay: minuteOfDay,
          ),
          inInclusiveRange(
            CalendarReminders.minAllDayMinutes,
            CalendarReminders.maxAllDayMinutes,
          ),
        );
      }
    }
  });
}
