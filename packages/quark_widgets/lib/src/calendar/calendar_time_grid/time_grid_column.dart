import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/calendar_event_item.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_event_chip.dart';
import '../calendar_labels.dart';
import 'time_grid_event_block.dart';
import 'time_grid_layout.dart';
import 'time_grid_slot.dart';

/// One day's column on `CalendarTimeGrid`: 24 hour slots, the day's timed
/// events laid over them, and the now line when [now] falls on [day].
///
/// On a touch platform (see [wantsTouchTargets]) every block is drawn at
/// least 48dp tall, so a quarter-hour event is still a target a finger can
/// hit; one drawn past its end sits beside whatever it then overlaps. Where
/// overlapping events split the column into lanes narrower than 48dp, and
/// [onCrowdTap] is given, the blocks take no tap of their own: one target
/// over the whole group calls [onCrowdTap], for the caller to open the day,
/// where the lanes are wide enough (#2939).
///
/// Key prefixes: its slots' `calendar_slot_` keys, its blocks'
/// `calendar_event_` keys, and `calendar_crowd_<yyyy-mm-dd>_<minute>` on a
/// crowded group's target, by the minute of the day it starts.
class TimeGridColumn extends StatelessWidget {
  /// Creates the column for [day].
  const TimeGridColumn({
    required this.day,
    required this.events,
    required this.hourHeight,
    required this.narrow,
    this.snug = false,
    this.now,
    this.leftEdge = false,
    this.onSlotTap,
    this.onEventTap,
    this.onCrowdTap,
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

  /// Whether the column is only just a touch target wide, so its blocks take
  /// all of it.
  final bool snug;

  /// The current time, or null to draw no now line.
  final DateTime? now;

  /// Whether to draw a hairline down the left edge, between two days.
  final bool leftEdge;

  /// Called with the hour whose empty slot was tapped.
  final ValueChanged<DateTime>? onSlotTap;

  /// Called with the event whose block was tapped.
  final ValueChanged<CalendarEventItem>? onEventTap;

  /// Called when a group of events too crowded to tap one by one is tapped.
  /// Null leaves each block its own tap, however narrow.
  final VoidCallback? onCrowdTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final touch = wantsTouchTargets(context);
    final minuteHeight = hourHeight / 60;
    final placements = layoutDay(
      day,
      events,
      minimumMinutes: touch
          ? ((kMinInteractiveDimension + blockGap) / minuteHeight).ceil()
          : minimumBlockMinutes,
    );
    final current = now;
    final showNow = current != null && CalendarDates.isSameDay(current, day);
    final onCrowdTap = touch ? this.onCrowdTap : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: leftEdge
            ? Border(left: BorderSide(color: tokens.border))
            : const Border(),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The room kept clear to a block's left, and to both its sides.
          final (left, clear) = snug
              ? (0.0, 0.0)
              : narrow
              ? (1.0, 2.0)
              : (2.0, 8.0);
          final width = constraints.maxWidth - clear;
          // Each crowded group's first minute, last minute and size.
          final crowds = <int, (int, int, int)>{};
          if (onCrowdTap != null) {
            for (final p in placements) {
              if (p.lanes > 1 &&
                  width / p.lanes - 2 < kMinInteractiveDimension) {
                final (start, end, count) =
                    crowds[p.group] ?? (p.startMinute, p.endMinute, 0);
                crowds[p.group] = (
                  math.min(start, p.startMinute),
                  math.max(end, p.endMinute),
                  count + 1,
                );
              }
            }
          }
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
                      blockGap,
                  left: left + width * placement.lane / placement.lanes,
                  width:
                      width / placement.lanes - (placement.lanes > 1 ? 2 : 0),
                  child: TimeGridEventBlock(
                    item: placement.item,
                    height:
                        (placement.endMinute - placement.startMinute) *
                            minuteHeight -
                        blockGap,
                    narrow: narrow,
                    onTap:
                        onEventTap == null ||
                            crowds.containsKey(placement.group)
                        ? null
                        : () => onEventTap!(placement.item),
                  ),
                ),
              for (final (start, end, count) in crowds.values)
                Positioned(
                  top: start * minuteHeight + 1,
                  height: (end - start) * minuteHeight - blockGap,
                  left: 0,
                  right: 0,
                  child: Semantics(
                    button: true,
                    label:
                        '$count events, '
                        'show ${CalendarLabels.dayTitle(day)}',
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: ValueKey(
                          'calendar_crowd_${CalendarDates.key(day)}_$start',
                        ),
                        onTap: onCrowdTap,
                      ),
                    ),
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
