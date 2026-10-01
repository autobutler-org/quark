/// Local calendar-date arithmetic for the calendar widgets and their callers.
///
/// Everything here works on wall-clock fields rather than durations: adding a
/// day builds a new `DateTime` from the next date, so a day across a daylight
/// saving change is still one date, never 23 or 25 hours off.
abstract final class CalendarDates {
  /// Midnight at the start of [d]'s date, in [d]'s own time zone.
  static DateTime dateOnly(DateTime d) => d.isUtc
      ? DateTime.utc(d.year, d.month, d.day)
      : DateTime(d.year, d.month, d.day);

  /// [d] moved by [days] dates, keeping its time of day.
  static DateTime addDays(DateTime d, int days) => d.isUtc
      ? DateTime.utc(d.year, d.month, d.day + days, d.hour, d.minute, d.second)
      : DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second);

  /// Whether [a] and [b] fall on the same date.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// [d]'s date as `yyyy-mm-dd`, the form every calendar key uses.
  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The first date of the week holding [d], a week starting on
  /// [firstWeekday] (`DateTime.sunday` or `DateTime.monday`, for instance).
  static DateTime startOfWeek(
    DateTime d, {
    int firstWeekday = DateTime.sunday,
  }) {
    final back = (d.weekday - firstWeekday) % 7;
    return addDays(dateOnly(d), -back);
  }

  /// The seven dates of the week holding [d].
  static List<DateTime> weekOf(
    DateTime d, {
    int firstWeekday = DateTime.sunday,
  }) {
    final start = startOfWeek(d, firstWeekday: firstWeekday);
    return [for (var i = 0; i < 7; i++) addDays(start, i)];
  }

  /// The dates a month grid shows for [month]'s month: whole weeks from the
  /// one holding the 1st to the one holding the last day, so 35 or 42 dates
  /// (28 for a February that fits exactly).
  static List<DateTime> monthGrid(
    DateTime month, {
    int firstWeekday = DateTime.sunday,
  }) {
    final first = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    final start = startOfWeek(first, firstWeekday: firstWeekday);
    final end = addDays(
      startOfWeek(last, firstWeekday: firstWeekday),
      7,
    ); // exclusive
    return [
      for (var day = start; day.isBefore(end); day = addDays(day, 1)) day,
    ];
  }
}
