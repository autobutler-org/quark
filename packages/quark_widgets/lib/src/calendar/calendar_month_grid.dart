import 'package:flutter/material.dart';

import '../models/calendar_event_item.dart';
import '../theme/quark_tokens.dart';
import 'calendar_dates.dart';
import 'calendar_empty_notice.dart';
import 'calendar_labels.dart';
import 'calendar_month_grid/month_day_cell.dart';

/// A month as a grid of whole weeks, each date listing the events on it.
///
/// The grid shows the weeks holding [month]'s first and last days, five or
/// six rows sharing the height it is given, so give it a bounded height (an
/// `Expanded`, say), never an unbounded scroll view. An event spanning several
/// dates is listed on each. Each cell shows as many events as fit and a
/// "+N more" line for the rest. On a narrow grid (a phone) the cells go dense
/// and drawn edge to edge: a title clipped to a few letters tells events apart
/// no better than nothing (#2541), so each date shows a colored dot per event,
/// up to [maxDots], and "+N" for the rest. Its accessible label reads every
/// title, and a tap opens the date, where they fit.
///
/// A month with no events on its own dates keeps its grid and adds a
/// [CalendarEmptyNotice] under it, "Nothing planned this month", whose
/// "Add an event" calls [onAddEvent] (#2538). It stays away while [isLoading],
/// so a month still on its way never reads as empty.
///
/// Rows start on [firstWeekday]; pass the locale's, from
/// `CalendarDates.firstWeekdayFromIndex`, and the same one the caller loaded
/// the span with (#2539).
///
/// Tapping a date calls [onDayTap], which is also what its "+N more" does:
/// the Day view is where every event on it fits. A long press calls
/// [onDayLongPress], and on desktop, hovering a date shows an add button that
/// calls [onAddTap]. Tapping an event calls [onEventTap] with a mouse; on a
/// touch platform, where an event's line is too thin to hit, that tap is the
/// date's too when there is an [onDayTap] (#2939). The date is then the one
/// target, and at least 48dp while the grid is at least 336dp wide and its
/// rows share 48dp each: a narrower phone, or one on its side, squeezes it
/// under that.
///
/// Key prefixes: `calendar_day_<yyyy-mm-dd>` on each date,
/// `calendar_add_<yyyy-mm-dd>` on its hover add button,
/// `calendar_more_<yyyy-mm-dd>` on its overflow line,
/// `calendar_event_<item.key>` on each event, and on a phone
/// `calendar_dots_<yyyy-mm-dd>` on a date's dots, `calendar_dot_<item.key>` on
/// each. `calendar_month_add` is the empty month's button.
///
/// ```dart
/// CalendarMonthGrid(
///   month: DateTime(2026, 9),
///   today: DateTime(2026, 9, 29),
///   events: controller.occurrences,
///   onDayTap: (day) => showDay(day),
///   onDayLongPress: (day) => createOn(day),
///   onEventTap: (item) => edit(item.eventId),
/// );
/// ```
class CalendarMonthGrid extends StatelessWidget {
  /// Creates the grid for [month].
  const CalendarMonthGrid({
    required this.month,
    required this.today,
    required this.events,
    this.selectedDay,
    this.firstWeekday = CalendarDates.defaultFirstWeekday,
    this.isLoading = false,
    this.onDayTap,
    this.onDayLongPress,
    this.onAddTap,
    this.onEventTap,
    this.onAddEvent,
    super.key,
  });

  /// Any date in the month to show.
  final DateTime month;

  /// Today's date, drawn with a filled marker when it is on the grid.
  final DateTime today;

  /// The occurrences to place, in any order. Those off the grid are ignored.
  final List<CalendarEventItem> events;

  /// The date drawn as selected, or null for none.
  final DateTime? selectedDay;

  /// The weekday each row starts on, [CalendarDates.defaultFirstWeekday]
  /// unless the caller passes the locale's.
  final int firstWeekday;

  /// Whether [events] is still loading, which holds back the empty notice.
  final bool isLoading;

  /// Called with the date that was tapped.
  final ValueChanged<DateTime>? onDayTap;

  /// Called with the date that was long-pressed.
  final ValueChanged<DateTime>? onDayLongPress;

  /// Called with the date whose hover add button was pressed. Null hides it.
  final ValueChanged<DateTime>? onAddTap;

  /// Called with the event whose chip was tapped. Not on a touch platform
  /// when [onDayTap] is given, where a tap on a chip is a tap on its date.
  final ValueChanged<CalendarEventItem>? onEventTap;

  /// Called by the empty month's "Add an event". Null hides the button.
  final VoidCallback? onAddEvent;

  /// The most dots a phone-sized date draws before "+N".
  static const int maxDots = 3;

  /// Below this width per column, cells draw dense.
  static const double denseColumnWidth = 90;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final days = CalendarDates.monthGrid(month, firstWeekday: firstWeekday);
    final rows = days.length ~/ 7;
    final byDay = eventsByDay(events);
    final empty =
        !isLoading &&
        !days.any(
          (day) =>
              day.month == month.month &&
              day.year == month.year &&
              byDay.containsKey(CalendarDates.key(day)),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxWidth / 7 < denseColumnWidth;
        final grid = Column(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.border)),
              ),
              child: Row(
                children: [
                  for (final day in days.take(7))
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: dense ? 6 : 8,
                          horizontal: dense ? 0 : 10,
                        ),
                        child: Text(
                          dense
                              ? CalendarLabels.weekdayNarrow(day.weekday)
                              : CalendarLabels.weekdayShort(
                                  day.weekday,
                                ).toUpperCase(),
                          textAlign: dense ? TextAlign.center : TextAlign.start,
                          semanticsLabel: CalendarLabels.weekday(day.weekday),
                          style: TextStyle(
                            fontSize: dense ? 11 : 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: dense ? 0 : 0.6,
                            color: tokens.secondaryForeground,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (var row = 0; row < rows; row++)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: MonthDayCell(
                          key: ValueKey(
                            'month_cell_${CalendarDates.key(days[row * 7 + col])}',
                          ),
                          day: days[row * 7 + col],
                          events:
                              byDay[CalendarDates.key(days[row * 7 + col])] ??
                              const [],
                          inMonth:
                              days[row * 7 + col].month == month.month &&
                              days[row * 7 + col].year == month.year,
                          isToday: CalendarDates.isSameDay(
                            days[row * 7 + col],
                            today,
                          ),
                          isSelected:
                              selectedDay != null &&
                              CalendarDates.isSameDay(
                                days[row * 7 + col],
                                selectedDay!,
                              ),
                          dense: dense,
                          maxDots: maxDots,
                          lastColumn: col == 6,
                          lastRow: row == rows - 1,
                          onTap: onDayTap == null
                              ? null
                              : () => onDayTap!(days[row * 7 + col]),
                          onLongPress: onDayLongPress == null
                              ? null
                              : () => onDayLongPress!(days[row * 7 + col]),
                          onAdd: onAddTap == null
                              ? null
                              : () => onAddTap!(days[row * 7 + col]),
                          onEventTap: onEventTap,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );

        final framed = dense
            ? ColoredBox(color: tokens.card, child: grid)
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.card,
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.radiusLg - 1),
                  child: grid,
                ),
              );
        if (!empty) return framed;
        // The grid is the product, so an empty month keeps it and says so
        // underneath rather than in its place.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: framed),
            Padding(
              padding: EdgeInsets.all(tokens.spacingSm),
              child: Center(
                child: CalendarEmptyNotice(
                  headline: 'Nothing planned this month',
                  buttonKey: const ValueKey('calendar_month_add'),
                  onAdd: onAddEvent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// [events] grouped by every date each covers, keyed by `CalendarDates.key`,
/// each date's list with all-day events first and then by start.
Map<String, List<CalendarEventItem>> eventsByDay(
  Iterable<CalendarEventItem> events,
) {
  final byDay = <String, List<CalendarEventItem>>{};
  for (final item in events) {
    for (final day in item.dates) {
      (byDay[CalendarDates.key(day)] ??= []).add(item);
    }
  }
  for (final list in byDay.values) {
    list.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.title.compareTo(b.title);
    });
  }
  return byDay;
}
