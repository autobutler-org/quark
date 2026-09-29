import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../calendar_labels.dart';

/// A week column's heading on `CalendarTimeGrid`: the weekday over the date,
/// the date filled with the accent color when it is today. Tapping it opens
/// that day.
///
/// Key prefixes: `calendar_day_header_<yyyy-mm-dd>`, set by the grid.
class TimeGridDayHeader extends StatelessWidget {
  /// Creates the heading for [day].
  const TimeGridDayHeader({
    required this.day,
    required this.isToday,
    this.onTap,
    super.key,
  });

  /// The date the column shows.
  final DateTime day;

  /// Whether [day] is today.
  final bool isToday;

  /// Called when the heading is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Semantics(
      button: onTap != null,
      label: CalendarLabels.dayTitle(day),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            spacing: 2,
            children: [
              Text(
                CalendarLabels.weekdayShort(day.weekday),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isToday ? tokens.primary : tokens.secondaryForeground,
                ),
              ),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: tokens.primary,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isToday
                        ? tokens.primaryForeground
                        : tokens.foreground,
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
