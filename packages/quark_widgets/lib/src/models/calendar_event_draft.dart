import 'package:flutter/foundation.dart';

import '../calendar/calendar_dates.dart';
import 'calendar_repeat.dart';

/// An event as `CalendarEventEditor` edits it: every field a person sets,
/// before it is saved.
///
/// Times are local. An all-day draft starts at midnight on its first date and
/// [end] is the midnight after its last, the same shape `CalendarEventItem`
/// has; [lastDate] is the inclusive date an editor shows. The `with…` methods
/// are the edits a form makes, each keeping the draft coherent: moving the
/// start keeps the length, and switching all day on or off rebuilds the times.
@immutable
class CalendarEventDraft {
  /// Creates a draft from its fields.
  const CalendarEventDraft({
    required this.start,
    required this.end,
    this.title = '',
    this.allDay = false,
    this.repeat = CalendarRepeat.none,
    this.repeatUntil,
    this.reminderMinutes,
    this.colorIndex = 0,
    this.location = '',
    this.notes = '',
  });

  /// A blank timed event from [start], an hour long.
  factory CalendarEventDraft.at(DateTime start) => CalendarEventDraft(
    start: start,
    end: start.add(const Duration(hours: 1)),
  );

  /// A blank all-day event on [day].
  factory CalendarEventDraft.allDayOn(DateTime day) {
    final date = CalendarDates.dateOnly(day);
    return CalendarEventDraft(
      start: date,
      end: CalendarDates.addDays(date, 1),
      allDay: true,
    );
  }

  /// When the event starts.
  final DateTime start;

  /// When it ends, exclusive.
  final DateTime end;

  /// What it is called; blank until typed.
  final String title;

  /// Whether it takes whole dates.
  final bool allDay;

  /// How it repeats.
  final CalendarRepeat repeat;

  /// The last date it repeats on, inclusive, or null to repeat forever. Read
  /// only while [repeat] is not none, so switching repeat off and on again
  /// keeps it.
  final DateTime? repeatUntil;

  /// Minutes before [start] its reminder is due, or null for none.
  final int? reminderMinutes;

  /// Which of `QuarkTokens.eventColors` it is drawn in.
  final int colorIndex;

  /// Where it happens.
  final String location;

  /// Free text.
  final String notes;

  /// The last date an all-day draft covers, or [end] for a timed one.
  DateTime get lastDate => allDay ? CalendarDates.addDays(end, -1) : end;

  /// Whether [end] falls after [start], the one rule a form checks before
  /// saving.
  bool get endsAfterStart => end.isAfter(start);

  /// Whether a repeating draft stops repeating on or after its first date,
  /// the other rule a form checks. True for a draft that does not repeat or
  /// repeats forever.
  bool get repeatEndsInTime =>
      repeat == CalendarRepeat.none ||
      repeatUntil == null ||
      !CalendarDates.dateOnly(
        repeatUntil!,
      ).isBefore(CalendarDates.dateOnly(start));

  /// [repeatUntil] while the draft repeats, else null: what is saved.
  DateTime? get savedRepeatUntil =>
      repeat == CalendarRepeat.none ? null : repeatUntil;

  /// A copy with the given fields replaced. Pass [clearReminder] to turn the
  /// reminder off and [clearRepeatUntil] to repeat forever, since a null
  /// [reminderMinutes] or [repeatUntil] means "keep".
  CalendarEventDraft copyWith({
    DateTime? start,
    DateTime? end,
    String? title,
    bool? allDay,
    CalendarRepeat? repeat,
    DateTime? repeatUntil,
    bool clearRepeatUntil = false,
    int? reminderMinutes,
    bool clearReminder = false,
    int? colorIndex,
    String? location,
    String? notes,
  }) => CalendarEventDraft(
    start: start ?? this.start,
    end: end ?? this.end,
    title: title ?? this.title,
    allDay: allDay ?? this.allDay,
    repeat: repeat ?? this.repeat,
    repeatUntil: clearRepeatUntil ? null : repeatUntil ?? this.repeatUntil,
    reminderMinutes: clearReminder
        ? null
        : reminderMinutes ?? this.reminderMinutes,
    colorIndex: colorIndex ?? this.colorIndex,
    location: location ?? this.location,
    notes: notes ?? this.notes,
  );

  /// Switches all day on or off. On, the draft covers the dates its times
  /// touched; off, it becomes 9 to 10 AM on its first date. A reminder is
  /// cleared, since the two kinds count from different starts.
  CalendarEventDraft withAllDay(bool on) {
    if (on == allDay) return this;
    final first = CalendarDates.dateOnly(start);
    if (on) {
      final last = CalendarDates.dateOnly(
        end.isAfter(start)
            ? end.subtract(const Duration(microseconds: 1))
            : start,
      );
      return copyWith(
        allDay: true,
        start: first,
        end: CalendarDates.addDays(last, 1),
        clearReminder: true,
      );
    }
    final nine = DateTime(first.year, first.month, first.day, 9);
    return copyWith(
      allDay: false,
      start: nine,
      end: nine.add(const Duration(hours: 1)),
      clearReminder: true,
    );
  }

  /// Moves the start to [date], keeping its time of day and the event's
  /// length.
  CalendarEventDraft withStartDate(DateTime date) {
    final moved = DateTime(
      date.year,
      date.month,
      date.day,
      start.hour,
      start.minute,
    );
    if (allDay) {
      final days = _datesBetween(start, end);
      return copyWith(start: moved, end: CalendarDates.addDays(moved, days));
    }
    return copyWith(start: moved, end: moved.add(end.difference(start)));
  }

  /// Moves the start to [hour]:[minute] on its date, keeping the length.
  CalendarEventDraft withStartTime(int hour, int minute) {
    final moved = DateTime(start.year, start.month, start.day, hour, minute);
    return copyWith(start: moved, end: moved.add(end.difference(start)));
  }

  /// Moves the end to [date]: the inclusive last date of an all-day draft, or
  /// the date a timed draft ends on at its current time.
  CalendarEventDraft withEndDate(DateTime date) {
    if (allDay) {
      return copyWith(
        end: CalendarDates.addDays(CalendarDates.dateOnly(date), 1),
      );
    }
    return copyWith(
      end: DateTime(date.year, date.month, date.day, end.hour, end.minute),
    );
  }

  /// Moves the end to [hour]:[minute] on its date.
  CalendarEventDraft withEndTime(int hour, int minute) =>
      copyWith(end: DateTime(end.year, end.month, end.day, hour, minute));

  static int _datesBetween(DateTime a, DateTime b) {
    var days = 0;
    for (
      var d = CalendarDates.dateOnly(a);
      d.isBefore(CalendarDates.dateOnly(b));
      d = CalendarDates.addDays(d, 1)
    ) {
      days++;
    }
    return days;
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarEventDraft &&
      other.start == start &&
      other.end == end &&
      other.title == title &&
      other.allDay == allDay &&
      other.repeat == repeat &&
      other.repeatUntil == repeatUntil &&
      other.reminderMinutes == reminderMinutes &&
      other.colorIndex == colorIndex &&
      other.location == location &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
    start,
    end,
    title,
    allDay,
    repeat,
    repeatUntil,
    reminderMinutes,
    colorIndex,
    location,
    notes,
  );
}
