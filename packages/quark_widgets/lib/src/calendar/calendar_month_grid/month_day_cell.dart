import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/calendar_event_item.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_event_chip.dart';
import '../calendar_labels.dart';
import 'month_day_dots.dart';

/// One date in `CalendarMonthGrid`: its number, as many of its [events] as fit,
/// and a "+N more" line for the rest. A [dense] cell draws a `MonthDayDots`
/// row instead of titles, and its accessible label reads every title.
///
/// It is stateful only for the pointer: hovering shows an add button in the
/// corner, the desktop stand-in for a long press.
///
/// On a touch platform (see [wantsTouchTargets]) a cell with an [onTap]
/// takes its chips' taps too: a 22px line is not a target a finger can hit,
/// so the whole cell is the one target and opens the date, where each event
/// is (#2939). A mouse still opens an event from its chip, and the hover add
/// button is a mouse's alone, at a mouse's size.
///
/// Key prefixes: `calendar_day_<yyyy-mm-dd>` on the cell,
/// `calendar_add_<yyyy-mm-dd>` on its add button, `calendar_more_<yyyy-mm-dd>`
/// on its overflow line, each event chip's own `calendar_event_` key, and a
/// dense cell's `calendar_dots_<yyyy-mm-dd>` and `calendar_dot_<item.key>`.
/// The overflow line and the dots have no tap of their own: a tap on them is a
/// tap on the cell.
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
    required this.maxDots,
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

  /// The most dots a [dense] cell draws before "+N".
  final int maxDots;

  /// Called when the cell or its overflow line is tapped.
  final VoidCallback? onTap;

  /// Called on a long press of the cell.
  final VoidCallback? onLongPress;

  /// Called with the event whose chip was tapped. Not on a touch platform
  /// when [onTap] is given, where a tap on a chip is a tap on the cell.
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
    final chipHeight = CalendarEventChip.height + 2;
    final headerHeight = dense ? 30.0 : 34.0;
    const moreHeight = 18.0;
    final count = widget.events.length;
    final onEventTap = wantsTouchTargets(context) && widget.onTap != null
        ? null
        : widget.onEventTap;

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

    // A dense cell draws no titles, so its label is where they are read.
    final titles = dense && count > 0
        ? ': ${widget.events.map((e) => e.title).join(', ')}'
        : '';
    final label =
        '${CalendarLabels.dayTitle(widget.day)}, '
        '${count == 0 ? 'no events' : '$count ${count == 1 ? 'event' : 'events'}'}'
        '$titles';

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
        // Large text can make a two-digit date wider than a phone's column;
        // it shrinks to fit there rather than overflow, and is untouched
        // anywhere it already fits.
        Flexible(
          child: FittedBox(fit: BoxFit.scaleDown, child: number),
        ),
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
      // Its own node, carrying the cell's taps: merged into the grid's, the
      // label and the button role ended up apart from the tap, and a screen
      // reader announced a button it could not press (#2603).
      child: Semantics(
        container: true,
        label: label,
        button: widget.onTap != null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
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
                  if (dense) {
                    return ClipRect(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: headerHeight, child: header),
                          if (count > 0 && room >= MonthDayDots.height)
                            MonthDayDots(
                              key: ValueKey('calendar_dots_$key'),
                              dateKey: key,
                              events: widget.events,
                              maxDots: widget.maxDots,
                            ),
                        ],
                      ),
                    );
                  }
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
                              onTap: onEventTap == null
                                  ? null
                                  : () => onEventTap(item),
                            ),
                          ),
                        if (shown < count)
                          SizedBox(
                            height: moreHeight,
                            // No tap of its own: the line does what tapping
                            // the cell does, and the cell is a target a
                            // finger can hit where this 18px line is not
                            // (#2605).
                            child: Padding(
                              key: ValueKey('calendar_more_$key'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Text(
                                '+${count - shown} more',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.secondaryForeground,
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
