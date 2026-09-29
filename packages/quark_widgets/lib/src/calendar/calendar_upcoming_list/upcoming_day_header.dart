import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_labels.dart';

/// A date's heading in `CalendarUpcomingList`: "Today", "Tomorrow" or the
/// weekday, then the date.
class UpcomingDayHeader extends StatelessWidget {
  /// Creates the heading for [day], worded relative to [today].
  const UpcomingDayHeader({required this.day, required this.today, super.key});

  /// The date the group holds.
  final DateTime day;

  /// Today's date.
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final String name;
    final String date;
    if (CalendarDates.isSameDay(day, today)) {
      name = 'Today';
      date = CalendarLabels.dayTitle(day);
    } else if (CalendarDates.isSameDay(
      day,
      CalendarDates.addDays(CalendarDates.dateOnly(today), 1),
    )) {
      name = 'Tomorrow';
      date = CalendarLabels.dayTitle(day);
    } else {
      name = CalendarLabels.weekday(day.weekday);
      date = '${CalendarLabels.month(day.month)} ${day.day}';
    }
    return Semantics(
      header: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.foreground,
              ),
            ),
            TextSpan(text: ' · $date'),
          ],
        ),
        style: TextStyle(fontSize: 13, color: tokens.secondaryForeground),
      ),
    );
  }
}
