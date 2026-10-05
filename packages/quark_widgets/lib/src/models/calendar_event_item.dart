import 'package:flutter/foundation.dart';

import '../calendar/calendar_dates.dart';
import 'calendar_repeat.dart';

/// One occurrence of a calendar event, as the calendar widgets draw it.
///
/// A repeating event reaches the widgets as one item per occurrence, already
/// expanded by the caller, all sharing [eventId]. Times are local wall-clock
/// times. An all-day item starts at midnight on its first date and [end] is
/// the midnight after its last, so a one-day event spans exactly one date.
@immutable
class CalendarEventItem {
  /// Creates an occurrence of event [eventId].
  const CalendarEventItem({
    required this.eventId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.colorIndex = 0,
    this.location = '',
    this.repeat = CalendarRepeat.none,
    this.repeatUntil,
    this.reminderMinutes,
  });

  /// The stored event this is an occurrence of.
  final int eventId;

  /// What the event is called.
  final String title;

  /// When this occurrence starts.
  final DateTime start;

  /// When it ends, exclusive.
  final DateTime end;

  /// Whether it takes whole dates rather than a time of day.
  final bool allDay;

  /// Which of `QuarkTokens.eventColors` it is drawn in.
  final int colorIndex;

  /// Where it happens; empty when not given.
  final String location;

  /// How the event repeats.
  final CalendarRepeat repeat;

  /// The last date the event repeats on, inclusive, or null when it repeats
  /// forever or not at all.
  final DateTime? repeatUntil;

  /// How many minutes before [start] its reminder is due, or null for none.
  /// Negative for an all-day event whose reminder falls on its own day.
  final int? reminderMinutes;

  /// Unique for this occurrence: the event id and the date it starts on, for
  /// example `7_2026-09-29`. Every calendar widget builds its keys from it.
  String get key => '${eventId}_${CalendarDates.key(start)}';

  /// When this occurrence's reminder is due, or null without one.
  DateTime? get reminderAt => reminderMinutes == null
      ? null
      : start.subtract(Duration(minutes: reminderMinutes!));

  /// Every local date this occurrence covers, in order.
  List<DateTime> get dates {
    final first = CalendarDates.dateOnly(start);
    // The last instant it covers is just before its exclusive end.
    final last = CalendarDates.dateOnly(
      end.isAfter(start) ? end.subtract(const Duration(microseconds: 1)) : end,
    );
    return [
      for (
        var day = first;
        !day.isAfter(last);
        day = CalendarDates.addDays(day, 1)
      )
        day,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarEventItem &&
      other.eventId == eventId &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.colorIndex == colorIndex &&
      other.location == location &&
      other.repeat == repeat &&
      other.repeatUntil == repeatUntil &&
      other.reminderMinutes == reminderMinutes;

  @override
  int get hashCode => Object.hash(
    eventId,
    title,
    start,
    end,
    allDay,
    colorIndex,
    location,
    repeat,
    repeatUntil,
    reminderMinutes,
  );
}
