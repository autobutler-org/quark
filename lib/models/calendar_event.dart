import 'package:quark_widgets/quark_widgets.dart';

/// A stored event of the household calendar, as `/api/v0/calendar/events`
/// returns it: a one-off event, or a repeating event's series.
///
/// The Quark stores times in UTC. A timed event's [start] and [end] are
/// instants; an all-day event's are midnight UTC standing for calendar dates,
/// with [end] exclusive. [localStart] and [localEnd] turn both into the local
/// wall-clock times the calendar widgets draw. A series' [repeatUntil] is a
/// date in the same way, and [localRepeatUntil] is it on the local calendar.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.notes = '',
    this.location = '',
    this.allDay = false,
    this.timeZone = '',
    this.repeat = CalendarRepeat.none,
    this.repeatUntil,
    this.reminderMinutes,
    this.colorIndex = 0,
    this.owner = '',
    this.mine = false,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    location: json['location'] as String? ?? '',
    start: DateTime.parse(json['start'] as String).toUtc(),
    end: DateTime.parse(json['end'] as String).toUtc(),
    allDay: json['allDay'] as bool? ?? false,
    timeZone: json['timeZone'] as String? ?? '',
    repeat: repeatFromWire(json['repeat'] as String?),
    // A Quark from before #2524 sends none, and a series without one
    // repeats forever.
    repeatUntil: switch (json['repeatUntil']) {
      final String until => DateTime.parse(until).toUtc(),
      _ => null,
    },
    reminderMinutes: json['reminderMinutes'] as int?,
    colorIndex: json['colorIndex'] as int? ?? 0,
    owner: json['owner'] as String? ?? '',
    mine: json['mine'] as bool? ?? false,
  );

  final int id;
  final String title;
  final String notes;
  final String location;

  /// The first occurrence's start, in UTC.
  final DateTime start;

  /// The first occurrence's end, in UTC, exclusive.
  final DateTime end;

  final bool allDay;

  /// The IANA zone the event was made in, when the client knew it.
  final String timeZone;

  final CalendarRepeat repeat;

  /// The last date the series repeats on, inclusive, as midnight UTC standing
  /// for that date; null repeats forever (#2524).
  final DateTime? repeatUntil;

  /// Minutes before the start its reminder is due, or null for none.
  final int? reminderMinutes;

  /// Which of `QuarkTokens.eventColors` it is drawn in.
  final int colorIndex;

  /// The username of the account that created it, or empty for an event
  /// with no owner (#2544).
  final String owner;

  /// Whether the signed-in account created it.
  final bool mine;

  /// The first occurrence's start on the local clock: midnight on its date
  /// for an all-day event, wherever the viewer is.
  DateTime get localStart =>
      allDay ? DateTime(start.year, start.month, start.day) : start.toLocal();

  /// The first occurrence's end on the local clock. See [localStart].
  DateTime get localEnd =>
      allDay ? DateTime(end.year, end.month, end.day) : end.toLocal();

  /// [repeatUntil] as a local date, the same date wherever it is read.
  DateTime? get localRepeatUntil => switch (repeatUntil) {
    final until? => DateTime(until.year, until.month, until.day),
    null => null,
  };

  /// This timed event with its first occurrence moved to run from [start] to
  /// [end] on the local clock, everything else kept: what the calendar shows
  /// while a drag's save is on its way.
  CalendarEvent movedTo(DateTime start, DateTime end) => CalendarEvent(
    id: id,
    title: title,
    notes: notes,
    location: location,
    start: start.toUtc(),
    end: end.toUtc(),
    allDay: allDay,
    timeZone: timeZone,
    repeat: repeat,
    repeatUntil: repeatUntil,
    reminderMinutes: reminderMinutes,
    colorIndex: colorIndex,
    owner: owner,
    mine: mine,
  );

  /// The event as the editor opens it.
  CalendarEventDraft toDraft() => CalendarEventDraft(
    title: title,
    start: localStart,
    end: localEnd,
    allDay: allDay,
    repeat: repeat,
    repeatUntil: localRepeatUntil,
    reminderMinutes: reminderMinutes,
    colorIndex: colorIndex,
    location: location,
    notes: notes,
  );

  /// Reads the wire name of a repeat preset; an unknown one is none.
  static CalendarRepeat repeatFromWire(String? name) => CalendarRepeat.values
      .firstWhere((r) => r.name == name, orElse: () => CalendarRepeat.none);

  /// The body of a create or update for [draft]: local times sent as UTC, and
  /// an all-day draft's dates, like a series' last date, as midnight UTC.
  static Map<String, dynamic> requestBody(
    CalendarEventDraft draft, {
    String timeZone = '',
  }) {
    String date(DateTime local) =>
        DateTime.utc(local.year, local.month, local.day).toIso8601String();
    String wire(DateTime local) =>
        draft.allDay ? date(local) : local.toUtc().toIso8601String();
    final until = draft.savedRepeatUntil;
    return {
      'title': draft.title.trim(),
      'notes': draft.notes,
      'location': draft.location.trim(),
      'start': wire(draft.start),
      'end': wire(draft.end),
      'allDay': draft.allDay,
      'timeZone': timeZone,
      'repeat': draft.repeat.name,
      'repeatUntil': until == null ? null : date(until),
      'reminderMinutes': draft.reminderMinutes,
      'colorIndex': draft.colorIndex,
    };
  }
}
