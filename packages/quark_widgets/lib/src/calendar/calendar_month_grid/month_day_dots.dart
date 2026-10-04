import 'package:flutter/material.dart';

import '../../models/calendar_event_item.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_event_chip.dart';

/// A phone-sized month date's events as marks: a dot in each event's color,
/// a short bar for an all-day one (the chip's shapes), up to [maxDots], then
/// "+N" for the rest.
///
/// Drawn instead of titles a narrow cell can only clip to a few letters
/// (#2541). It is decoration: the cell's label reads the titles, and a tap on
/// it is a tap on the cell. It scales down rather than overflow when large
/// text leaves the "+N" wider than the cell.
///
/// Key prefixes: `calendar_dot_<item.key>` on each mark and
/// `calendar_more_<dateKey>` on the "+N".
class MonthDayDots extends StatelessWidget {
  /// Creates the marks for [events] on the date keyed [dateKey].
  const MonthDayDots({
    required this.dateKey,
    required this.events,
    required this.maxDots,
    super.key,
  });

  /// The date's `CalendarDates.key`, for the "+N" key.
  final String dateKey;

  /// The occurrences on the date, in the order to mark them.
  final List<CalendarEventItem> events;

  /// The most marks drawn before "+N".
  final int maxDots;

  /// The row's height.
  static const double height = 14;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final extra = events.length - maxDots;

    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in events.take(maxDots))
                Container(
                  key: ValueKey('calendar_dot_${item.key}'),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  width: item.allDay ? 10 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: eventColor(tokens, item.colorIndex),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              if (extra > 0)
                Padding(
                  key: ValueKey('calendar_more_$dateKey'),
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    '+$extra',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: tokens.secondaryForeground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
