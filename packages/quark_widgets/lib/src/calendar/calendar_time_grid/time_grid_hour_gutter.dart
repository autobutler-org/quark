import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_labels.dart';

/// The hour labels down the left of `CalendarTimeGrid`, and the current time
/// in the accent color beside the now line when [now] is on screen.
class TimeGridHourGutter extends StatelessWidget {
  /// Creates a gutter [width] wide with hours [hourHeight] apart.
  const TimeGridHourGutter({
    required this.width,
    required this.hourHeight,
    required this.days,
    this.now,
    super.key,
  });

  /// The gutter's width.
  final double width;

  /// The height of one hour.
  final double hourHeight;

  /// The dates on show, to tell whether [now] is among them.
  final List<DateTime> days;

  /// The current time, or null for no time label.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final current = now;
    final showNow =
        current != null &&
        days.any((day) => CalendarDates.isSameDay(day, current));
    final nowTop = showNow
        ? (current.hour * 60 + current.minute) * hourHeight / 60
        : 0.0;

    return SizedBox(
      width: width,
      height: hourHeight * 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Midnight is the top edge; its label would sit above the grid.
          for (var hour = 1; hour < 24; hour++)
            // Hide an hour label the now label would overlap.
            if (!showNow || (hour * hourHeight - nowTop).abs() > 12)
              Positioned(
                top: hour * hourHeight - 8,
                right: tokens.spacingSm,
                child: ExcludeSemantics(
                  child: Text(
                    CalendarLabels.hour(hour, use24Hour: use24Hour),
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.secondaryForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
          if (showNow)
            Positioned(
              top: nowTop - 8,
              right: tokens.spacingSm,
              child: Text(
                CalendarLabels.time(
                  current,
                  use24Hour: use24Hour,
                  compact: true,
                ),
                semanticsLabel:
                    'Now, ${CalendarLabels.time(current, use24Hour: use24Hour)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: tokens.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
