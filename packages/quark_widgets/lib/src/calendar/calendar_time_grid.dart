import 'package:flutter/material.dart';

import '../models/calendar_event_item.dart';
import '../theme/quark_tokens.dart';
import 'calendar_dates.dart';
import 'calendar_empty_notice.dart';
import 'calendar_time_grid/time_grid_all_day_row.dart';
import 'calendar_time_grid/time_grid_column.dart';
import 'calendar_time_grid/time_grid_day_header.dart';
import 'calendar_time_grid/time_grid_hour_gutter.dart';

/// An hourly timeline for one date or a week: the Day and Week views.
///
/// Each date in [days] gets a column from midnight to midnight. Timed events
/// sit on it as blocks, overlapping ones side by side. All-day events sit in a
/// row above it that keeps its height when it is empty. With more than one date
/// each column is headed by its weekday and date. The timeline scrolls; it
/// opens at [initialHour], and the now line shows while [now] falls on a date
/// on show. Give it a bounded height.
///
/// Hours are 56 pixels tall on a wide screen and 64 on a phone, where fingers
/// need the room. On a phone a week's seven columns are too narrow for more
/// than an event's title; the accessible label still reads the whole event.
///
/// A single date with no events at all keeps its timeline and centers a
/// [CalendarEmptyNotice] over it, "Free day", whose "Add an event" calls
/// [onAddEvent] (#2538); the hours around it still create at their hour. It
/// stays away while [isLoading], and a week says nothing: its empty columns
/// already read as free.
///
/// Key prefixes: `calendar_slot_<yyyy-mm-dd>_<hour>` on each hour,
/// `calendar_day_header_<yyyy-mm-dd>` on each week column's heading,
/// `calendar_all_day_more_<yyyy-mm-dd>` on an all-day overflow line,
/// `calendar_now_line` on the now line, `calendar_event_<item.key>` on
/// each event, and `calendar_day_add` on the empty day's button.
///
/// ```dart
/// CalendarTimeGrid(
///   days: CalendarDates.weekOf(anchor),
///   today: today,
///   now: now,
///   events: controller.occurrences,
///   onSlotTap: (start) => createAt(start),
///   onEventTap: (item) => edit(item.eventId),
///   onDayTap: (day) => showDay(day),
/// );
/// ```
class CalendarTimeGrid extends StatefulWidget {
  /// Creates a timeline for [days].
  const CalendarTimeGrid({
    required this.days,
    required this.today,
    required this.events,
    this.now,
    this.initialHour = 8,
    this.onSlotTap,
    this.onEventTap,
    this.onDayTap,
    this.onAddEvent,
    this.isLoading = false,
    super.key,
  });

  /// The dates to show, one column each, in order.
  final List<DateTime> days;

  /// Today's date, whose week heading is marked.
  final DateTime today;

  /// The occurrences to place. Those on no date in [days] are ignored.
  final List<CalendarEventItem> events;

  /// The current time, which draws the now line. Null draws none.
  final DateTime? now;

  /// The hour scrolled to the top when the timeline first shows.
  final int initialHour;

  /// Called with the start of the empty hour that was tapped.
  final ValueChanged<DateTime>? onSlotTap;

  /// Called with the event that was tapped.
  final ValueChanged<CalendarEventItem>? onEventTap;

  /// Called with the date whose heading, or all-day "+N" line, was tapped.
  final ValueChanged<DateTime>? onDayTap;

  /// Called by the empty day's "Add an event". Null hides the button.
  final VoidCallback? onAddEvent;

  /// Whether [events] is still loading, which holds back the empty notice.
  final bool isLoading;

  /// The width below which the grid lays out for a phone.
  static const double compactWidth = 600;

  @override
  State<CalendarTimeGrid> createState() => _CalendarTimeGridState();
}

class _CalendarTimeGridState extends State<CalendarTimeGrid> {
  ScrollController? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll ??= ScrollController(
      initialScrollOffset: widget.initialHour * _hourHeight(context),
    );
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  double _hourHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).width < CalendarTimeGrid.compactWidth
      ? 64
      : 56;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < CalendarTimeGrid.compactWidth;
    final hourHeight = _hourHeight(context);
    final gutter = compact ? 52.0 : 64.0;
    final days = widget.days;
    final narrow = compact && days.length > 1;
    final onDayTap = widget.onDayTap;
    final empty =
        days.length == 1 &&
        !widget.isLoading &&
        !widget.events.any(
          (e) => e.dates.any((d) => CalendarDates.isSameDay(d, days.single)),
        );

    return ColoredBox(
      color: tokens.card,
      child: Column(
        children: [
          if (days.length > 1)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.border)),
              ),
              child: Row(
                children: [
                  SizedBox(width: gutter),
                  for (final day in days)
                    Expanded(
                      child: TimeGridDayHeader(
                        key: ValueKey(
                          'calendar_day_header_${CalendarDates.key(day)}',
                        ),
                        day: day,
                        isToday: CalendarDates.isSameDay(day, widget.today),
                        onTap: onDayTap == null ? null : () => onDayTap(day),
                      ),
                    ),
                ],
              ),
            ),
          TimeGridAllDayRow(
            days: days,
            events: widget.events,
            gutterWidth: gutter,
            narrow: narrow,
            onEventTap: widget.onEventTap,
            onMoreTap: onDayTap,
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TimeGridHourGutter(
                          width: gutter,
                          hourHeight: hourHeight,
                          days: days,
                          now: widget.now,
                        ),
                        for (final (index, day) in days.indexed)
                          Expanded(
                            child: TimeGridColumn(
                              day: day,
                              events: widget.events,
                              hourHeight: hourHeight,
                              narrow: narrow,
                              now: widget.now,
                              leftEdge: index > 0,
                              onSlotTap: widget.onSlotTap,
                              onEventTap: widget.onEventTap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (empty)
                  // Only the card takes taps; around it the hours do.
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(tokens.spacingMd),
                      child: CalendarEmptyNotice(
                        headline: 'Free day',
                        subtext: 'Nothing scheduled',
                        buttonKey: const ValueKey('calendar_day_add'),
                        onAdd: widget.onAddEvent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
