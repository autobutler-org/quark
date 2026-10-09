import 'package:flutter/material.dart';

import '../models/calendar_event_item.dart';
import '../theme/quark_tokens.dart';
import 'calendar_dates.dart';
import 'calendar_empty_notice.dart';
import 'calendar_event_chip.dart';
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
/// opens at [initialHour] and keeps its place when [days] changes, so stepping
/// to the next week leaves the same hours on show (#2887). The now line shows
/// while [now] falls on a date on show. Give it a bounded height.
///
/// Hours are 56 pixels tall on a wide screen and 64 on a phone, where fingers
/// need the room. On a phone a week's seven columns are too narrow for more
/// than an event's title; the accessible label still reads the whole event.
///
/// On a touch platform (one whose theme pads Material's tap targets) the
/// targets are at least 48dp (#2939): an event is drawn at least that tall
/// however short it is, an all-day event's line answers taps across 48dp, a
/// phone week's hour gutter narrows to short labels ("9a") so each of its
/// columns is 48dp wide on a 360dp phone, and a week's overlapping events,
/// when their lanes are narrower than that, share one target that calls
/// [onDayTap], because the Day view is where each has room. A desktop keeps
/// its mouse-sized targets and its layout. What stays under 48dp: a week on
/// a phone narrower than 360dp, or boxed into less than the screen's width
/// (phone or not is read from the screen, not the box); a Day with more
/// events at once than fit side by side at 48dp each; and a week's narrow
/// lanes when there is no [onDayTap] to hand them to.
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
/// `calendar_crowd_<yyyy-mm-dd>_<minute>` on a week's crowded group,
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

  /// Called with the date whose heading, all-day "+N" line, or crowded
  /// group of events was tapped.
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
    final days = widget.days;
    final narrow = compact && days.length > 1;
    // A phone week on a touch platform gives the gutter's room to its seven
    // columns, which is what makes each a 48dp target wide at 360dp.
    final snug = narrow && wantsTouchTargets(context);
    final gutter = snug
        ? 24.0
        : compact
        ? 52.0
        : 64.0;
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
            snug: snug,
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
                          narrow: snug,
                          now: widget.now,
                        ),
                        for (final (index, day) in days.indexed)
                          Expanded(
                            child: TimeGridColumn(
                              day: day,
                              events: widget.events,
                              hourHeight: hourHeight,
                              narrow: narrow,
                              snug: snug,
                              now: widget.now,
                              leftEdge: index > 0,
                              onSlotTap: widget.onSlotTap,
                              onEventTap: widget.onEventTap,
                              onCrowdTap: days.length > 1 && onDayTap != null
                                  ? () => onDayTap(day)
                                  : null,
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
