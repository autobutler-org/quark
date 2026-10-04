import 'package:flutter/material.dart';

import '../models/calendar_event_item.dart';
import '../theme/quark_tokens.dart';
import 'calendar_labels.dart';

/// One event on a line: how the month grid and the all-day row list events.
///
/// An all-day event is a filled bar and a timed one a colored dot before its
/// start time, so the two differ in shape as well as color. [dense] is the
/// phone size: smaller type, and no time, which a narrow cell has no room for.
/// The color is `QuarkTokens.eventColors[item.colorIndex]`.
///
/// Key prefixes: `calendar_event_<item.key>` on the chip, for example
/// `calendar_event_7_2026-09-29`.
///
/// ```dart
/// CalendarEventChip(
///   item: occurrence,
///   onTap: () => openEditor(occurrence.eventId),
/// );
/// ```
class CalendarEventChip extends StatelessWidget {
  /// Creates a chip for [item].
  const CalendarEventChip({
    required this.item,
    this.dense = false,
    this.onTap,
    super.key,
  });

  /// The occurrence to show.
  final CalendarEventItem item;

  /// Whether to draw the smaller, time-less phone chip.
  final bool dense;

  /// Called when the chip is tapped. Null leaves it inert.
  final VoidCallback? onTap;

  /// The chip's height at the regular size.
  static const double height = 22;

  /// The chip's height when [dense].
  static const double denseHeight = 18;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final color = eventColor(tokens, item.colorIndex);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final fontSize = dense ? 10.5 : 12.0;
    final radius = BorderRadius.circular(tokens.radiusSm);
    final time = CalendarLabels.time(
      item.start,
      use24Hour: use24Hour,
      compact: true,
    );

    return Semantics(
      button: onTap != null,
      label: '${item.title}, ${item.allDay ? 'all day' : time}',
      excludeSemantics: true,
      // Excluding the child's semantics drops its tap too, so the node
      // carries its own, or a screen reader cannot press it (#2603).
      onTap: onTap,
      child: Material(
        color: item.allDay ? color.withValues(alpha: 0.24) : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          key: ValueKey('calendar_event_${item.key}'),
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            height: dense ? denseHeight : height,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 3 : 6),
              child: Row(
                children: [
                  if (!item.allDay) ...[
                    Container(
                      width: dense ? 5 : 7,
                      height: dense ? 5 : 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: dense ? 3 : 6),
                  ],
                  if (!item.allDay && !dense) ...[
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: tokens.secondaryForeground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: dense
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: item.allDay
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: tokens.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The color an event with [colorIndex] is drawn in: one of
/// `QuarkTokens.eventColors`, or the first for an index the tokens lack.
Color eventColor(QuarkTokens tokens, int colorIndex) {
  final colors = tokens.eventColors;
  if (colors.isEmpty) return tokens.primary;
  return colorIndex >= 0 && colorIndex < colors.length
      ? colors[colorIndex]
      : colors.first;
}
