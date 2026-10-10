import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/calendar_event_item.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_event_chip.dart';
import '../calendar_labels.dart';
import 'time_grid_event_block.dart';
import 'time_grid_event_mover.dart';
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
/// With [onEventReschedule] each block can be dragged or moved from the
/// keyboard: see `TimeGridEventMover`. A crowded group's blocks cannot,
/// because the Day view is where each has room. The column draws [preview],
/// a drag in flight anywhere on the grid, where it falls on [day].
///
/// Key prefixes: its slots' `calendar_slot_` keys, its blocks'
/// `calendar_event_` keys, `calendar_crowd_<yyyy-mm-dd>_<minute>` on a
/// crowded group's target, by the minute of the day it starts, and
/// `calendar_drag_preview` on [preview].
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
    this.days = const [],
    this.preview,
    this.focusKey,
    this.onSlotTap,
    this.onEventTap,
    this.onCrowdTap,
    this.onPreview,
    this.onEventReschedule,
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

  /// Every date the grid shows, in order: as far as a move can carry an event.
  final List<DateTime> days;

  /// An event as a drag in flight would leave it, drawn over the column where
  /// it falls on [day]. Null draws none.
  final CalendarEventItem? preview;

  /// The `CalendarEventItem.key` of the block that takes the focus when it
  /// first shows: the one a key press just moved here from another column.
  final String? focusKey;

  /// Called with the hour whose empty slot was tapped.
  final ValueChanged<DateTime>? onSlotTap;

  /// Called with the event whose block was tapped.
  final ValueChanged<CalendarEventItem>? onEventTap;

  /// Called when a group of events too crowded to tap one by one is tapped.
  /// Null leaves each block its own tap, however narrow.
  final VoidCallback? onCrowdTap;

  /// Called with an event as the drag in flight on it would leave it, and
  /// with null when that drag ends.
  final ValueChanged<CalendarEventItem?>? onPreview;

  /// Called with an event and the copy of it a drag or a key press moved.
  /// `fromKeyboard` says which. Null leaves the blocks where they are.
  final void Function(
    CalendarEventItem item,
    CalendarEventItem moved, {
    required bool fromKeyboard,
  })?
  onEventReschedule;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final touch = wantsTouchTargets(context);
    final minuteHeight = hourHeight / 60;
    final minimumMinutes = touch
        ? ((kMinInteractiveDimension + blockGap) / minuteHeight).ceil()
        : minimumBlockMinutes;
    final placements = layoutDay(day, events, minimumMinutes: minimumMinutes);
    final preview = this.preview;
    final onEventReschedule = this.onEventReschedule;
    double blockHeight(TimeGridPlacement p) =>
        (p.endMinute - p.startMinute) * minuteHeight - blockGap;
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
          final blocks = [
            for (final placement in placements)
              TimeGridEventBlock(
                item: placement.item,
                height: blockHeight(placement),
                narrow: narrow,
                autofocus: placement.item.key == focusKey,
                onTap: onEventTap == null || crowds.containsKey(placement.group)
                    ? null
                    : () => onEventTap!(placement.item),
              ),
          ];
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
              for (final (index, placement) in placements.indexed)
                Positioned(
                  // Keyed, so a block keeps its focus when a move from the
                  // keyboard changes the order of the day.
                  key: ValueKey(placement.item.key),
                  top: placement.startMinute * minuteHeight + 1,
                  height: blockHeight(placement),
                  left: left + width * placement.lane / placement.lanes,
                  width:
                      width / placement.lanes - (placement.lanes > 1 ? 2 : 0),
                  child:
                      onEventReschedule == null ||
                          crowds.containsKey(placement.group)
                      ? blocks[index]
                      : TimeGridEventMover(
                          item: placement.item,
                          days: days,
                          height: blockHeight(placement),
                          hourHeight: hourHeight,
                          columnWidth: constraints.maxWidth,
                          onPreview: (preview) => onPreview?.call(preview),
                          onReschedule: (moved, {required fromKeyboard}) =>
                              onEventReschedule(
                                placement.item,
                                moved,
                                fromKeyboard: fromKeyboard,
                              ),
                          child: blocks[index],
                        ),
                ),
              if (preview != null)
                for (final placement in layoutDay(day, [
                  preview,
                ], minimumMinutes: minimumMinutes))
                  Positioned(
                    top: placement.startMinute * minuteHeight + 1,
                    height: blockHeight(placement),
                    left: left,
                    width: width,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: TimeGridEventBlock(
                          item: placement.item,
                          height: blockHeight(placement),
                          narrow: narrow,
                          preview: true,
                        ),
                      ),
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
