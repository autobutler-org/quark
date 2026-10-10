import '../models/calendar_event_item.dart';
import 'calendar_dates.dart';
import 'calendar_labels.dart';

/// When a reminder is due, and how a due one is worded: shared by the
/// Upcoming list, the reminder bar, and the page that decides which bar to
/// show.
abstract final class CalendarReminders {
  /// The time of day an all-day reminder falls at until a person picks
  /// another, in minutes past midnight: 9 AM.
  static const int defaultAllDayMinuteOfDay = 9 * 60;

  /// The least and most reminder minutes an all-day event may store, the
  /// bounds the Quark enforces: 11:59 PM on the day itself, back to the
  /// midnight a week before.
  static const int minAllDayMinutes = -(_minutesPerDay - 1);

  /// See [minAllDayMinutes].
  static const int maxAllDayMinutes = 7 * _minutesPerDay;

  static const int _minutesPerDay = 24 * 60;

  /// The reminder minutes of an all-day event reminded [daysBefore] dates
  /// before it starts (0 is the day itself) at [minuteOfDay] minutes past
  /// midnight. An all-day reminder counts back from the event's midnight, so
  /// the day before at 9 AM is 900 and the day itself at 9 AM is -540.
  static int allDayMinutes({
    required int daysBefore,
    required int minuteOfDay,
  }) => daysBefore * _minutesPerDay - minuteOfDay;

  /// How many dates before an all-day event its reminder of [minutes] falls
  /// on: 0 for the day itself, 1 for the day before.
  static int allDayDaysBefore(int minutes) => (minutes / _minutesPerDay).ceil();

  /// The time of day an all-day reminder of [minutes] falls at, in minutes
  /// past midnight. With [allDayDaysBefore] it undoes [allDayMinutes].
  static int allDayMinuteOfDay(int minutes) =>
      allDayDaysBefore(minutes) * _minutesPerDay - minutes;

  /// Whether [item]'s reminder is due at [now]: its time has come, and the
  /// event is still ahead. A timed event is ahead until it starts. An all-day
  /// one is ahead until its last date ends, so a reminder at 9 AM on the day
  /// itself counts.
  static bool isDue(CalendarEventItem item, DateTime now) {
    final at = item.reminderAt;
    if (at == null || now.isBefore(at)) return false;
    return now.isBefore(item.allDay ? item.end : item.start);
  }

  /// A due reminder in a few words: "Starts in 20 min" for a timed event;
  /// "Today", "Tomorrow" or the date for an all-day one.
  static String dueLabel(CalendarEventItem item, DateTime now) {
    if (!item.allDay) {
      return CalendarLabels.startsIn(item.start.difference(now));
    }
    final today = CalendarDates.dateOnly(now);
    if (!item.start.isAfter(today)) return 'Today';
    if (CalendarDates.isSameDay(item.start, CalendarDates.addDays(today, 1))) {
      return 'Tomorrow';
    }
    return CalendarLabels.dayTitleShort(item.start);
  }
}
