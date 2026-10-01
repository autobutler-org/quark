import 'package:flutter/foundation.dart';

import '../../models/calendar_event_item.dart';
import '../calendar_dates.dart';

/// Where one timed event sits in a day column of `CalendarTimeGrid`.
@immutable
class TimeGridPlacement {
  /// Places [item] from [startMinute] to [endMinute] of its day, in lane
  /// [lane] of [lanes] side-by-side lanes.
  const TimeGridPlacement({
    required this.item,
    required this.startMinute,
    required this.endMinute,
    required this.lane,
    required this.lanes,
  });

  /// The occurrence placed.
  final CalendarEventItem item;

  /// Minutes past the day's midnight where the block starts, 0 to 1440.
  final int startMinute;

  /// Minutes past the day's midnight where the block ends, exclusive.
  final int endMinute;

  /// Which lane, from the left, the block takes.
  final int lane;

  /// How many lanes its group of overlapping events splits the column into.
  final int lanes;
}

/// The shortest a block is drawn, so a five-minute event is still tappable.
const int minimumBlockMinutes = 20;

/// Places the timed events among [events] that fall on [day].
///
/// Each is clipped to the day, so an event past midnight shows in both
/// columns. Minutes are wall-clock minutes, so a block sits at the time its
/// event says even on a daylight saving day. Events that overlap share the
/// width: each group of overlapping events is split into as many lanes as it
/// needs at its busiest, and each event takes the leftmost lane free when it
/// starts.
List<TimeGridPlacement> layoutDay(
  DateTime day,
  Iterable<CalendarEventItem> events,
) {
  final dayStart = CalendarDates.dateOnly(day);
  final dayEnd = CalendarDates.addDays(dayStart, 1);

  final spans = <(CalendarEventItem, int, int)>[];
  for (final item in events) {
    if (item.allDay) continue;
    if (!item.end.isAfter(dayStart) || !item.start.isBefore(dayEnd)) continue;
    final start = item.start.isAfter(dayStart)
        ? item.start.hour * 60 + item.start.minute
        : 0;
    final end = item.end.isBefore(dayEnd)
        ? item.end.hour * 60 + item.end.minute
        : 24 * 60;
    final drawnEnd = end - start < minimumBlockMinutes
        ? (start + minimumBlockMinutes).clamp(0, 24 * 60)
        : end;
    spans.add((item, start, drawnEnd));
  }
  spans.sort((a, b) {
    final byStart = a.$2.compareTo(b.$2);
    if (byStart != 0) return byStart;
    // Longer first, so a short event sits beside a long one, not under it.
    return b.$3.compareTo(a.$3);
  });

  final placements = <TimeGridPlacement>[];
  var group = <(CalendarEventItem, int, int, int)>[];
  var laneEnds = <int>[];
  var groupEnd = -1;

  void closeGroup() {
    for (final (item, start, end, lane) in group) {
      placements.add(
        TimeGridPlacement(
          item: item,
          startMinute: start,
          endMinute: end,
          lane: lane,
          lanes: laneEnds.length,
        ),
      );
    }
    group = [];
    laneEnds = [];
  }

  for (final (item, start, end) in spans) {
    if (start >= groupEnd) closeGroup();
    var lane = laneEnds.indexWhere((laneEnd) => laneEnd <= start);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(end);
    } else {
      laneEnds[lane] = end;
    }
    group.add((item, start, end, lane));
    if (end > groupEnd) groupEnd = end;
  }
  closeGroup();
  return placements;
}
