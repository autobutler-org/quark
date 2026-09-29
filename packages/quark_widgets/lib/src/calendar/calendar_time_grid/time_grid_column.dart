import 'package:flutter/material.dart';

import '../../models/calendar_event_item.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import 'time_grid_event_block.dart';
import 'time_grid_layout.dart';
import 'time_grid_slot.dart';

/// One day's column on `CalendarTimeGrid`: 24 hour slots, the day's timed
/// events laid over them, and the now line when [now] falls on [day].
///
/// Key prefixes: its slots' `calendar_slot_` keys and its blocks'
/// `calendar_event_` keys.
class TimeGridColumn extends StatelessWidget {
  /// Creates the column for [day].
  const TimeGridColumn({
    required this.day,
    required this.events,
    required this.hourHeight,
    required this.narrow,
    this.now,
    this.leftEdge = false,
    this.onSlotTap,
    this.onEventTap,
    super.key,
  });

  /// The date this column shows.
  final DateTime day;

  /// Occurrences to place; those not on [day] and all-day ones are skipped.
  final List<CalendarEventItem> events;

  /// The height of one hour.
  final double hourHeight;

  /// Whether the column is a narrow week column on a phone.
  final bool narrow;

  /// The current time, or null to draw no now line.
  final DateTime? now;

  /// Whether to draw a hairline down the left edge, between two days.
  final bool leftEdge;

  /// Called with the hour whose empty slot was tapped.
  final ValueChanged<DateTime>? onSlotTap;

  /// Called with the event whose block was tapped.
  final ValueChanged<CalendarEventItem>? onEventTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final placements = layoutDay(day, events);
    final current = now;
    final showNow = current != null && CalendarDates.isSameDay(current, day);
    final minuteHeight = hourHeight / 60;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: leftEdge
            ? Border(left: BorderSide(color: tokens.border))
            : const Border(),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth - (narrow ? 2 : 8);
          return Stack(
            children: [
              Column(
                children: [
                  for (var hour = 0; hour < 24; hour++)
                    TimeGridSlot(
                      start: DateTime(day.year, day.month, day.day, hour),
                      height: hourHeight,
                      showHint: !narrow && constraints.maxWidth > 140,
                      onTap: onSlotTap == null
                          ? null
                          : () => onSlotTap!(
                              DateTime(day.year, day.month, day.day, hour),
                            ),
                    ),
                ],
              ),
              for (final placement in placements)
                Positioned(
                  top: placement.startMinute * minuteHeight + 1,
                  height:
                      (placement.endMinute - placement.startMinute) *
                          minuteHeight -
                      3,
                  left:
                      (narrow ? 1 : 2) +
                      width * placement.lane / placement.lanes,
                  width:
                      width / placement.lanes - (placement.lanes > 1 ? 2 : 0),
                  child: TimeGridEventBlock(
                    item: placement.item,
                    height:
                        (placement.endMinute - placement.startMinute) *
                            minuteHeight -
                        3,
                    narrow: narrow,
                    onTap: onEventTap == null
                        ? null
                        : () => onEventTap!(placement.item),
                  ),
                ),
              if (showNow)
                Positioned(
                  top: (current.hour * 60 + current.minute) * minuteHeight - 1,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      key: const ValueKey('calendar_now_line'),
                      height: 2,
                      color: tokens.primary,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
