import 'package:flutter/material.dart';

import '../../models/calendar_event_item.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_event_chip.dart';
import '../calendar_month_grid.dart';

/// The all-day row above `CalendarTimeGrid`'s timeline, one cell per date.
///
/// It keeps its height with nothing in it, so the timeline below never jumps
/// when an all-day event comes or goes. A single day says so when it has none.
/// A cell shows up to [maxPerDay] events and a "+N" line for the rest, which
/// opens that day.
///
/// Key prefixes: `calendar_all_day_more_<yyyy-mm-dd>` on a cell's overflow
/// line, and each chip's own `calendar_event_` key.
class TimeGridAllDayRow extends StatelessWidget {
  /// Creates the row for [days].
  const TimeGridAllDayRow({
    required this.days,
    required this.events,
    required this.gutterWidth,
    required this.narrow,
    this.maxPerDay = 2,
    this.onEventTap,
    this.onMoreTap,
    super.key,
  });

  /// The dates on show, one cell each.
  final List<DateTime> days;

  /// Occurrences to place; only the all-day ones are shown.
  final List<CalendarEventItem> events;

  /// The width of the hour gutter to its left, which holds the row's label.
  final double gutterWidth;

  /// Whether the cells are narrow week columns on a phone.
  final bool narrow;

  /// The most events a cell lists before its "+N" line.
  final int maxPerDay;

  /// Called with the event whose chip was tapped.
  final ValueChanged<CalendarEventItem>? onEventTap;

  /// Called with the date whose "+N" line was tapped.
  final ValueChanged<DateTime>? onMoreTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final byDay = eventsByDay(events.where((e) => e.allDay));
    final muted = TextStyle(fontSize: 11, color: tokens.secondaryForeground);

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: gutterWidth,
              child: Padding(
                padding: EdgeInsets.only(right: tokens.spacingSm),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('All day', maxLines: 1, style: muted),
                ),
              ),
            ),
            for (final (index, day) in days.indexed)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: index == 0
                        ? const Border()
                        : Border(left: BorderSide(color: tokens.border)),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: narrow ? 1 : 4,
                    vertical: 6,
                  ),
                  alignment: Alignment.centerLeft,
                  child: switch (byDay[CalendarDates.key(day)] ?? const []) {
                    final List<CalendarEventItem> none when none.isEmpty =>
                      days.length == 1
                          ? Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                'No all-day events',
                                style: muted.copyWith(fontSize: 13),
                              ),
                            )
                          : const SizedBox.shrink(),
                    final List<CalendarEventItem> dayEvents => Column(
                      spacing: 2,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in dayEvents.take(
                          dayEvents.length > maxPerDay
                              ? maxPerDay - 1
                              : maxPerDay,
                        ))
                          CalendarEventChip(
                            item: item,
                            dense: narrow,
                            onTap: onEventTap == null
                                ? null
                                : () => onEventTap!(item),
                          ),
                        if (dayEvents.length > maxPerDay)
                          InkWell(
                            key: ValueKey(
                              'calendar_all_day_more_${CalendarDates.key(day)}',
                            ),
                            onTap: onMoreTap == null
                                ? null
                                : () => onMoreTap!(day),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              child: Text(
                                '+${dayEvents.length - maxPerDay + 1}',
                                style: muted.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
