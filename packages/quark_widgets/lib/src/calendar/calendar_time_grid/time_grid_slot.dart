import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_labels.dart';

/// One hour of one day on `CalendarTimeGrid`: the empty space an event is
/// created from.
///
/// It is stateful only for the pointer: hovering shows a dashed "New event at"
/// hint, so a desktop user can see that the empty timeline is tappable. The
/// hint is a live hover and nothing more (#2886): a pointer with a button held
/// is dragging, not pointing, so it shows none, and the hint goes when the slot
/// moves to another hour under a resting pointer or is tapped. The next move
/// brings it back.
///
/// It takes taps and a screen reader's press but not the keyboard's focus: a
/// week's 168 hours in the Tab order buried the events behind them (#3185).
///
/// Key prefixes: `calendar_slot_<yyyy-mm-dd>_<hour>`, for example
/// `calendar_slot_2026-09-29_10`.
class TimeGridSlot extends StatefulWidget {
  /// Creates the slot starting at [start], [height] pixels tall.
  const TimeGridSlot({
    required this.start,
    required this.height,
    required this.showHint,
    required this.hovered,
    this.onTap,
    this.onEnter,
    this.onHover,
    this.onExit,
    super.key,
  });

  /// The hour this slot starts.
  final DateTime start;

  /// The slot's height: one hour of the timeline.
  final double height;

  /// Whether the column is wide enough to show the hover hint's words.
  final bool showHint;

  /// Whether the grid is showing this hour's hover hint.
  ///
  /// The grid keeps one of these for the whole timeline. The slot paints it
  /// and does not decide it (#3558).
  final bool hovered;

  /// Called when the slot is tapped. Null leaves it inert.
  final VoidCallback? onTap;

  /// Called when a pointer enters this hour. Null while [onTap] is null.
  final void Function(PointerEnterEvent event)? onEnter;

  /// Called when a pointer moves within this hour. Null while [onTap] is null.
  final void Function(PointerHoverEvent event)? onHover;

  /// Called when a pointer leaves this hour. Null while [onTap] is null.
  final void Function(PointerExitEvent event)? onExit;

  @override
  State<TimeGridSlot> createState() => _TimeGridSlotState();
}

class _TimeGridSlotState extends State<TimeGridSlot> {
  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = CalendarLabels.time(widget.start, use24Hour: use24Hour);
    final onTap = widget.onTap;
    // The grid owns the hint. Painting a local flag is what left a slot lit
    // after the pointer had moved on (#3558).
    final hovered = widget.hovered && onTap != null;

    return MouseRegion(
      onEnter: onTap == null ? null : widget.onEnter,
      onHover: onTap == null ? null : widget.onHover,
      onExit: onTap == null ? null : widget.onExit,
      child: Semantics(
        button: onTap != null,
        label: 'New event at $time, ${CalendarLabels.dayTitle(widget.start)}',
        excludeSemantics: true,
        // Excluding the child's semantics drops its tap too, so the node
        // carries its own, or a screen reader cannot press it (#2603).
        onTap: onTap,
        // Quark turns the web semantics tree on for every user (#2599). A
        // node with a tap action is then a click target, and a flick that
        // finishes inside this hour arrives as a tap and opens New event
        // instead of paging (#3251). Transparent hit testing lets the
        // pointer through to the drag. The action stays for a real tap and
        // for a screen reader.
        hitTestBehavior: SemanticsHitTestBehavior.transparent,
        child: InkWell(
          key: ValueKey(
            'calendar_slot_${CalendarDates.key(widget.start)}_${widget.start.hour}',
          ),
          onTap: onTap,
          canRequestFocus: false,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border)),
            ),
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
            child: hovered
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      border: Border.all(
                        color: tokens.primary.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        spacing: 6,
                        children: [
                          Icon(
                            QuarkIcons.add_rounded,
                            size: 15,
                            color: tokens.primary,
                          ),
                          if (widget.showHint)
                            Flexible(
                              child: Text(
                                'New event at $time',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
