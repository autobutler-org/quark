/// How a calendar event repeats: never, or one of the simple presets.
///
/// There is no rule editor behind these. Weekly keeps the weekday of the first
/// occurrence and monthly its day of the month, skipping months that lack it.
enum CalendarRepeat {
  /// A one-off event.
  none,

  /// Every day at the same time.
  daily,

  /// Every week on the same weekday.
  weekly,

  /// Every month on the same date.
  monthly,
}
