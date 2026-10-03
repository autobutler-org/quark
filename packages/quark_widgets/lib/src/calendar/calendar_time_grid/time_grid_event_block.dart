import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/calendar_event_item.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_event_chip.dart';
import '../calendar_labels.dart';

/// One timed event drawn as a block on `CalendarTimeGrid`'s timeline.
///
/// What it shows depends on the room it has: a short block is one line (title
/// and time side by side), a tall one adds the location, and a [narrow] one
/// (a week column on a phone) has room for its title alone. The accessible
/// label always carries the title, the times, and the location.
///
/// Key prefixes: `calendar_event_<item.key>` on the block.
class TimeGridEventBlock extends StatelessWidget {
  /// Creates the block for [item], [height] pixels tall.
  const TimeGridEventBlock({
    required this.item,
    required this.height,
    this.narrow = false,
    this.onTap,
    super.key,
  });

  /// The occurrence to draw.
  final CalendarEventItem item;

  /// The block's height, from its duration.
  final double height;

  /// Whether the block is too narrow for anything but its title.
  final bool narrow;

  /// Called when the block is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final color = eventColor(tokens, item.colorIndex);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final range = CalendarLabels.timeRange(
      item.start,
      item.end,
      use24Hour: use24Hour,
    );
    final radius = BorderRadius.circular(tokens.radiusMd);
    final oneLine = height < 40 && !narrow;
    final showLocation = !narrow && item.location.isNotEmpty && height >= 64;
    final showReminder = !narrow && oneLine && item.reminderMinutes != null;

    final title = Text(
      item.title,
      maxLines: narrow ? 3 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: narrow ? 11 : 13,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: tokens.foreground,
      ),
    );
    final meta = TextStyle(fontSize: 12, color: tokens.secondaryForeground);

    return Semantics(
      button: onTap != null,
      label: [
        item.title,
        range,
        if (item.location.isNotEmpty) item.location,
      ].join(', '),
      excludeSemantics: true,
      // Excluding the child's semantics drops its tap too, so the node
      // carries its own, or a screen reader cannot press it (#2603).
      onTap: onTap,
      child: Material(
        color: Color.alphaBlend(color.withValues(alpha: 0.2), tokens.card),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('calendar_event_${item.key}'),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 4 : 10,
              vertical: oneLine ? 0 : (narrow ? 3 : 5),
            ),
            child: oneLine
                ? Row(
                    spacing: tokens.spacingSm,
                    children: [
                      Flexible(child: title),
                      Flexible(
                        child: Text(
                          range,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: meta,
                        ),
                      ),
                      if (showReminder) ...[
                        const Spacer(),
                        Icon(
                          QuarkIcons.notifications_outlined,
                          size: 13,
                          color: tokens.secondaryForeground,
                        ),
                      ],
                    ],
                  )
                // A block shorter than its lines clips them rather than
                // overflowing: the label above still reads them all.
                : OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 1,
                      children: [
                        title,
                        if (!narrow)
                          Text(
                            range,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: meta,
                          ),
                        if (showLocation)
                          Row(
                            spacing: 4,
                            children: [
                              Icon(
                                QuarkIcons.location_on_outlined,
                                size: 13,
                                color: tokens.secondaryForeground,
                              ),
                              Flexible(
                                child: Text(
                                  item.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: meta,
                                ),
                              ),
                            ],
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
