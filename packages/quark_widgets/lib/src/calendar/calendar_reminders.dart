import '../models/calendar_event_item.dart';
import 'calendar_dates.dart';
import 'calendar_labels.dart';

/// When a reminder is due, and how a due one is worded: shared by the
/// Upcoming list, the reminder bar, and the page that decides which bar to
/// show.
abstract final class CalendarReminders {
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
