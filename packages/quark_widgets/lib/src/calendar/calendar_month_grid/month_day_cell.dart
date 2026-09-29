import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/calendar_event_item.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_event_chip.dart';
import '../calendar_labels.dart';

/// One date in `CalendarMonthGrid`: its number, as many of its [events] as fit,
/// and a "+N more" line for the rest.
///
/// It is stateful only for the pointer: hovering shows an add button in the
/// corner, the desktop stand-in for a long press.
///
/// Key prefixes: `calendar_day_<yyyy-mm-dd>` on the cell,
/// `calendar_add_<yyyy-mm-dd>` on its add button, `calendar_more_<yyyy-mm-dd>`
/// on its overflow line, and each event chip's own `calendar_event_` key.
class MonthDayCell extends StatefulWidget {
  /// Creates the cell for [day].
  const MonthDayCell({
    required this.day,
    required this.events,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.dense,
    required this.lastColumn,
    required this.lastRow,
    this.onTap,
    this.onLongPress,
    this.onEventTap,
    this.onAdd,
    super.key,
  });

  /// The date this cell shows.
  final DateTime day;

  /// The occurrences on [day], in the order to list them.
  final List<CalendarEventItem> events;

  /// Whether [day] belongs to the month on show, rather than padding a week.
  final bool inMonth;

  /// Whether [day] is today.
  final bool isToday;

  /// Whether [day] is the selected date.
  final bool isSelected;

  /// Whether to draw the phone-sized cell.
  final bool dense;

  /// Whether the cell sits in the grid's last column and draws no right edge.
  final bool lastColumn;

  /// Whether the cell sits in the grid's last row and draws no bottom edge.
  final bool lastRow;

  /// Called when the cell or its overflow line is tapped.
  final VoidCallback? onTap;

  /// Called on a long press of the cell.
  final VoidCallback? onLongPress;

  /// Called with the event whose chip was tapped.
  final ValueChanged<CalendarEventItem>? onEventTap;

  /// Called from the hover add button. Null hides it.
  final VoidCallback? onAdd;

  @override
  State<MonthDayCell> createState() => _MonthDayCellState();
}

class _MonthDayCellState extends State<MonthDayCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final key = CalendarDates.key(widget.day);
    final dense = widget.dense;
    final chipHeight =
        (dense ? CalendarEventChip.denseHeight : CalendarEventChip.height) + 2;
    final headerHeight = dense ? 30.0 : 34.0;
    final moreHeight = dense ? 16.0 : 18.0;
    final count = widget.events.length;

    final Color background;
    if (widget.isSelected) {
      background = Color.alphaBlend(
        tokens.primary.withValues(alpha: 0.06),
        tokens.card,
      );
    } else if (_hovered) {
      background = Color.alphaBlend(
        tokens.foreground.withValues(alpha: 0.04),
        widget.inMonth ? tokens.card : tokens.sidebar,
      );
    } else {
      background = widget.inMonth ? tokens.card : tokens.sidebar;
    }

    final hairline = BorderSide(color: tokens.border);
    final border = widget.isSelected
        ? Border.all(color: tokens.primary, width: 2)
        : Border(
            right: widget.lastColumn ? BorderSide.none : hairline,
            bottom: widget.lastRow ? BorderSide.none : hairline,
          );

    final label =
        '${CalendarLabels.dayTitle(widget.day)}, '
        '${count == 0 ? 'no events' : '$count ${count == 1 ? 'event' : 'events'}'}';

    final number = Container(
      constraints: BoxConstraints(minWidth: widget.dense ? 24 : 28),
      height: widget.dense ? 24 : 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: widget.isToday
          ? BoxDecoration(
              color: tokens.primary,
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: Text(
        '${widget.day.day}',
        style: TextStyle(
          fontSize: widget.dense ? 12.5 : 13,
          fontWeight: widget.isToday
              ? FontWeight.w700
              : widget.inMonth
              ? FontWeight.w500
              : FontWeight.w400,
          color: widget.isToday
              ? tokens.primaryForeground
              : widget.inMonth
              ? tokens.foreground
              : tokens.secondaryForeground,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    final onAdd = widget.onAdd;
    final header = Row(
      mainAxisAlignment: widget.dense
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceBetween,
      children: [
        number,
        if (!widget.dense && _hovered && onAdd != null)
          SizedBox.square(
            dimension: 26,
            child: IconButton(
              key: ValueKey('calendar_add_$key'),
              tooltip: 'Add event on ${CalendarLabels.dayTitle(widget.day)}',
              onPressed: onAdd,
              padding: EdgeInsets.zero,
              iconSize: 15,
              style: IconButton.styleFrom(
                foregroundColor: tokens.secondaryForeground,
                backgroundColor: tokens.input,
                side: BorderSide(color: tokens.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                ),
              ),
              icon: const Icon(QuarkIcons.add_rounded),
            ),
          ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        label: label,
        button: widget.onTap != null,
        child: Material(
          color: background,
          child: InkWell(
            key: ValueKey('calendar_day_$key'),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Container(
              decoration: BoxDecoration(border: border),
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 2 : tokens.spacingXs + 2,
                vertical: tokens.spacingXs,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final room = constraints.maxHeight - headerHeight;
                  final fits = math.max(0, room ~/ chipHeight);
                  var shown = math.min(count, fits);
                  if (shown < count) {
                    // The overflow line takes the room of one more chip when
                    // one is needed.
                    shown = math
                        .max(0, (room - moreHeight) ~/ chipHeight)
                        .clamp(0, count);
                  }
                  return ClipRect(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: headerHeight, child: header),
                        for (final item in widget.events.take(shown))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: CalendarEventChip(
                              item: item,
                              dense: dense,
                              onTap: widget.onEventTap == null
                                  ? null
                                  : () => widget.onEventTap!(item),
                            ),
                          ),
                        if (shown < count)
                          SizedBox(
                            height: moreHeight,
                            child: InkWell(
                              key: ValueKey('calendar_more_$key'),
                              onTap: widget.onTap,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: dense ? 3 : 6,
                                ),
                                child: Text(
                                  dense
                                      ? '+${count - shown}'
                                      : '+${count - shown} more',
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: dense ? 10.5 : 12,
                                    fontWeight: FontWeight.w500,
                                    color: tokens.secondaryForeground,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
