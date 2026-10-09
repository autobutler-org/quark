import 'package:flutter/material.dart';
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
/// Key prefixes: `calendar_slot_<yyyy-mm-dd>_<hour>`, for example
/// `calendar_slot_2026-09-29_10`.
class TimeGridSlot extends StatefulWidget {
  /// Creates the slot starting at [start], [height] pixels tall.
  const TimeGridSlot({
    required this.start,
    required this.height,
    required this.showHint,
    this.onTap,
    super.key,
  });

  /// The hour this slot starts.
  final DateTime start;

  /// The slot's height: one hour of the timeline.
  final double height;

  /// Whether the column is wide enough to show the hover hint's words.
  final bool showHint;

  /// Called when the slot is tapped. Null leaves it inert.
  final VoidCallback? onTap;

  @override
  State<TimeGridSlot> createState() => _TimeGridSlotState();
}

class _TimeGridSlotState extends State<TimeGridSlot> {
  bool _hovered = false;

  void _hover(bool hovered) {
    if (hovered != _hovered) setState(() => _hovered = hovered);
  }

  @override
  void didUpdateWidget(TimeGridSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.start != oldWidget.start) _hovered = false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = CalendarLabels.time(widget.start, use24Hour: use24Hour);
    final onTap = widget.onTap;

    // A press is the start of a tap or a swipe, neither of them a hover.
    return Listener(
      onPointerDown: onTap == null ? null : (_) => _hover(false),
      child: MouseRegion(
        onEnter: onTap == null ? null : (event) => _hover(event.buttons == 0),
        onHover: onTap == null ? null : (_) => _hover(true),
        onExit: onTap == null ? null : (_) => _hover(false),
        child: Semantics(
          button: onTap != null,
          label: 'New event at $time, ${CalendarLabels.dayTitle(widget.start)}',
          excludeSemantics: true,
          // Excluding the child's semantics drops its tap too, so the node
          // carries its own, or a screen reader cannot press it (#2603).
          onTap: onTap,
          child: InkWell(
            key: ValueKey(
              'calendar_slot_${CalendarDates.key(widget.start)}_${widget.start.hour}',
            ),
            onTap: onTap,
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
              child: _hovered
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
      ),
    );
  }
}
