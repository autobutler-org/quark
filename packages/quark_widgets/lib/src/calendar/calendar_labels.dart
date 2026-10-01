import '../models/calendar_repeat.dart';
import 'calendar_dates.dart';

/// The English words and times the calendar widgets and their pages show.
///
/// One place for them so a title, a chip and a reminder all spell a time the
/// same way, and so localizing the calendar later means changing this file.
/// Times follow [use24Hour], which a widget reads from
/// `MediaQuery.alwaysUse24HourFormatOf`.
abstract final class CalendarLabels {
  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// The month's full name, January for 1.
  static String month(int month) => _months[month - 1];

  /// The month's three-letter name, Jan for 1.
  static String monthShort(int month) => _months[month - 1].substring(0, 3);

  /// The weekday's full name, Monday for `DateTime.monday`.
  static String weekday(int weekday) => _weekdays[weekday - 1];

  /// The weekday's three-letter name, Mon for `DateTime.monday`.
  static String weekdayShort(int weekday) =>
      _weekdays[weekday - 1].substring(0, 3);

  /// The weekday's initial, M for `DateTime.monday`.
  static String weekdayNarrow(int weekday) =>
      _weekdays[weekday - 1].substring(0, 1);

  /// "September 2026".
  static String monthTitle(DateTime d) => '${month(d.month)} ${d.year}';

  /// "Sep 2026".
  static String monthTitleShort(DateTime d) =>
      '${monthShort(d.month)} ${d.year}';

  /// "Tuesday, September 29".
  static String dayTitle(DateTime d) =>
      '${weekday(d.weekday)}, ${month(d.month)} ${d.day}';

  /// "Tue, Sep 29".
  static String dayTitleShort(DateTime d) =>
      '${weekdayShort(d.weekday)}, ${monthShort(d.month)} ${d.day}';

  /// "Tue, Sep 29, 2026", for a date field.
  static String date(DateTime d) => '${dayTitleShort(d)}, ${d.year}';

  /// The span of a week or any run of dates: "Sep 27 – Oct 3, 2026", or with
  /// [short] "Sep 27 – Oct 3". A run within one month reads "Sep 6 – 12".
  static String range(DateTime first, DateTime last, {bool short = false}) {
    final start = '${monthShort(first.month)} ${first.day}';
    final end = first.month == last.month && first.year == last.year
        ? '${last.day}'
        : '${monthShort(last.month)} ${last.day}';
    return short ? '$start – $end' : '$start – $end, ${last.year}';
  }

  /// A time of day: "9:00 AM", "21:00" with [use24Hour], or with [compact]
  /// "9am" and "12:30pm", the form a month chip has room for.
  static String time(
    DateTime t, {
    bool use24Hour = false,
    bool compact = false,
  }) {
    final minutes = t.minute.toString().padLeft(2, '0');
    if (use24Hour) {
      return compact
          ? '${t.hour}:$minutes'
          : '${t.hour.toString().padLeft(2, '0')}:$minutes';
    }
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final meridiem = t.hour < 12 ? 'AM' : 'PM';
    if (compact) {
      final clock = t.minute == 0 ? '$hour' : '$hour:$minutes';
      return '$clock${meridiem.toLowerCase()}';
    }
    return '$hour:$minutes $meridiem';
  }

  /// An hour line's label: "9 AM", "12 PM", or "09:00" with [use24Hour].
  static String hour(int hour, {bool use24Hour = false}) {
    if (use24Hour) return '${hour.toString().padLeft(2, '0')}:00';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h ${hour < 12 ? 'AM' : 'PM'}';
  }

  /// "4:00 – 4:45 PM", naming AM or PM once when both ends share it, and the
  /// end's date too when it falls on a later day.
  static String timeRange(
    DateTime start,
    DateTime end, {
    bool use24Hour = false,
  }) {
    final endText = time(end, use24Hour: use24Hour);
    final endLabel = CalendarDates.isSameDay(start, end)
        ? endText
        : '${dayTitleShort(end)}, $endText';
    if (!use24Hour &&
        CalendarDates.isSameDay(start, end) &&
        (start.hour < 12) == (end.hour < 12)) {
      final startText = time(start);
      return '${startText.substring(0, startText.length - 3)} – $endLabel';
    }
    return '${time(start, use24Hour: use24Hour)} – $endLabel';
  }

  /// A repeat preset in plain words, from the first occurrence [start]:
  /// "Every week on Tuesday", "Every month on the 29th".
  static String repeat(CalendarRepeat repeat, DateTime start) =>
      switch (repeat) {
        CalendarRepeat.none => 'Does not repeat',
        CalendarRepeat.daily => 'Every day',
        CalendarRepeat.weekly => 'Every week on ${weekday(start.weekday)}',
        CalendarRepeat.monthly =>
          'Every month on the ${_ordinal(start.day)}'
              '${start.day > 28 ? ', skipping months without one' : ''}',
      };

  /// A repeat preset's one-word name: "Weekly".
  static String repeatShort(CalendarRepeat repeat) => switch (repeat) {
    CalendarRepeat.none => 'Never',
    CalendarRepeat.daily => 'Daily',
    CalendarRepeat.weekly => 'Weekly',
    CalendarRepeat.monthly => 'Monthly',
  };

  /// When a reminder fires, relative to its event: "15 min before",
  /// "1 hour before", "At start". An all-day event counts back from its
  /// midnight, so it reads as a day and a clock time: "Day before, 9 AM".
  static String reminder(
    int minutes, {
    bool allDay = false,
    bool use24Hour = false,
  }) {
    if (allDay) {
      // Minutes past the midnight the event starts on, and how many dates
      // before it that falls.
      final daysBefore = (minutes / (24 * 60)).ceil();
      final clock = daysBefore * 24 * 60 - minutes;
      final fires = DateTime(2000, 1, 1, clock ~/ 60, clock % 60);
      final at = !use24Hour && fires.minute == 0
          ? hour(fires.hour)
          : time(fires, use24Hour: use24Hour);
      return switch (daysBefore) {
        <= 0 => 'On the day, $at',
        1 => 'Day before, $at',
        _ => '$daysBefore days before, $at',
      };
    }
    if (minutes == 0) return 'At start';
    if (minutes % (24 * 60) == 0) {
      final days = minutes ~/ (24 * 60);
      return days == 1 ? '1 day before' : '$days days before';
    }
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return hours == 1 ? '1 hour before' : '$hours hours before';
    }
    return '$minutes min before';
  }

  /// How long until an event starts, for a due reminder: "Starts in 20 min",
  /// "Starts in 1 h 5 min", or "Starting now" once it is under a minute.
  static String startsIn(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 1) return 'Starting now';
    if (minutes < 60) return 'Starts in $minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? 'Starts in $hours h' : 'Starts in $hours h $rest min';
  }

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }
}
