import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import '../calendar_dates.dart';
import '../calendar_labels.dart';

/// One hour of one day on `CalendarTimeGrid`: the empty space an event is
/// created from.
///
/// It is stateful only for the pointer: hovering shows a dashed "New event at"
/// hint, so a desktop user can see that the empty timeline is tappable.
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

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = CalendarLabels.time(widget.start, use24Hour: use24Hour);
    final onTap = widget.onTap;

    return MouseRegion(
      onEnter: onTap == null ? null : (_) => setState(() => _hovered = true),
      onExit: onTap == null ? null : (_) => setState(() => _hovered = false),
      child: Semantics(
        button: onTap != null,
        label: 'New event at $time, ${CalendarLabels.dayTitle(widget.start)}',
        excludeSemantics: true,
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
    );
  }
}
