import 'package:flutter/foundation.dart';

import 'calendar_event_item.dart';

/// One date's events, as `CalendarUpcomingList` groups them.
@immutable
class CalendarDayEvents {
  /// Groups [events] under [day].
  const CalendarDayEvents({required this.day, required this.events});

  /// The date, at midnight.
  final DateTime day;

  /// Its occurrences, in the order to list them.
  final List<CalendarEventItem> events;
}
