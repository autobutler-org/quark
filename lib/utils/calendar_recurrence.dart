import 'package:quark/models/calendar_event.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Expands stored events into the occurrences that touch [from, to), in local
/// time, sorted by start (#2491).
///
/// The Quark stores a repeating event once; this is where its preset turns
/// into dates. Every occurrence keeps the first one's wall-clock time, so a
/// weekly 9 AM event is at 9 AM on both sides of a daylight saving change
/// rather than drifting an hour. Weekly keeps the weekday, and monthly keeps
/// the day of the month, skipping months without it (no February 30th). A
/// series with a last date stops after it, on the viewer's calendar (#2524).
List<CalendarEventItem> expandOccurrences(
  Iterable<CalendarEvent> events,
  DateTime from,
  DateTime to,
) {
  final items = <CalendarEventItem>[];
  for (final event in events) {
    final last = event.localRepeatUntil;
    final stop = last == null ? to : CalendarDates.addDays(last, 1);
    for (final start in _occurrenceStarts(
      event,
      from,
      stop.isBefore(to) ? stop : to,
    )) {
      final end = _endFor(event, start);
      if (!end.isAfter(from) || !start.isBefore(to)) continue;
      items.add(
        CalendarEventItem(
          eventId: event.id,
          title: event.title,
          start: start,
          end: end,
          allDay: event.allDay,
          colorIndex: event.colorIndex,
          location: event.location,
          repeat: event.repeat,
          repeatUntil: last,
          reminderMinutes: event.reminderMinutes,
        ),
      );
    }
  }
  items.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.eventId.compareTo(b.eventId);
  });
  return items;
}

/// The most occurrences one event yields for one range, a guard against a
/// range far wider than any view asks for.
const int _maxOccurrences = 1000;

/// The occurrence of [event] starting at [start] ends the same length later:
/// the same number of dates for an all-day event, the same duration for a
/// timed one.
DateTime _endFor(CalendarEvent event, DateTime start) {
  final first = event.localStart;
  final last = event.localEnd;
  if (event.allDay) {
    return CalendarDates.addDays(start, _daysBetween(first, last));
  }
  return start.add(last.difference(first));
}

/// Every occurrence start of [event] that could overlap [from, to): starting
/// before [to], and late enough that its length reaches [from].
Iterable<DateTime> _occurrenceStarts(
  CalendarEvent event,
  DateTime from,
  DateTime to,
) sync* {
  final first = event.localStart;
  if (event.repeat == CalendarRepeat.none) {
    yield first;
    return;
  }

  // Skip whole steps that end before [from]: an occurrence can reach back at
  // most its own length, in dates.
  final spanDays = _daysBetween(first, event.localEnd) + 1;
  final behind = _daysBetween(first, from) - spanDays;

  switch (event.repeat) {
    case CalendarRepeat.none:
      return;
    case CalendarRepeat.daily:
    case CalendarRepeat.weekly:
      final step = event.repeat == CalendarRepeat.daily ? 1 : 7;
      var k = behind > 0 ? behind ~/ step : 0;
      for (var n = 0; n < _maxOccurrences; n++, k++) {
        final start = CalendarDates.addDays(first, k * step);
        if (!start.isBefore(to)) return;
        yield start;
      }
    case CalendarRepeat.monthly:
      var k = behind > 0 ? (behind ~/ 31) : 0;
      for (var n = 0; n < _maxOccurrences; n++, k++) {
        final start = DateTime(
          first.year,
          first.month + k,
          first.day,
          first.hour,
          first.minute,
        );
        // DateTime rolls February 30th over into March: that month has no
        // occurrence, but a later one might.
        if (start.day != first.day) {
          if (DateTime(first.year, first.month + k).isAfter(to)) return;
          continue;
        }
        if (!start.isBefore(to)) return;
        yield start;
      }
  }
}

/// Whole dates from [a]'s date to [b]'s, negative when [b] is earlier.
/// Counted on UTC dates so a daylight saving day is still one date.
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
