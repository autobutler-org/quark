import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/calendar_event_item.dart';
import '../../models/calendar_repeat.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_event_chip.dart';
import '../calendar_labels.dart';
import '../calendar_reminders.dart';

/// One event in `CalendarUpcomingList`: when, what, where and how it repeats,
/// and its reminder.
///
/// A reminder that is due (see `CalendarReminders.isDue`) shows as a
/// warning-tinted "Starts in 20 min", or "Today" for an all-day event, instead
/// of the bell: in the MVP this list is the only place a reminder surfaces.
///
/// Key prefixes: `calendar_upcoming_<item.key>` on the row.
class UpcomingEventRow extends StatelessWidget {
  /// Creates the row for [item], judged against [now].
  const UpcomingEventRow({
    required this.item,
    required this.now,
    required this.compact,
    this.onTap,
    super.key,
  });

  /// The occurrence to show.
  final CalendarEventItem item;

  /// The current time, which decides whether its reminder is due.
  final DateTime now;

  /// Whether the row sits in a phone-width list: the reminder shrinks to its
  /// bell, and a due reminder moves under the title.
  final bool compact;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final color = eventColor(tokens, item.colorIndex);
    final due = CalendarReminders.isDue(item, now);
    final when = item.allDay
        ? 'All day'
        : CalendarLabels.time(item.start, use24Hour: use24Hour);
    final span = item.allDay
        ? ''
        : CalendarLabels.timeRange(item.start, item.end, use24Hour: use24Hour);
    final reminder = item.reminderMinutes == null
        ? null
        : CalendarLabels.reminder(
            item.reminderMinutes!,
            allDay: item.allDay,
            use24Hour: use24Hour,
          );
    final meta = [
      if (span.isNotEmpty) span,
      if (item.location.isNotEmpty) item.location,
      if (item.repeat != CalendarRepeat.none)
        CalendarLabels.repeatShort(item.repeat),
    ];
    final metaStyle = TextStyle(
      fontSize: 12.5,
      color: tokens.secondaryForeground,
    );

    final duePill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.warning.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          Icon(
            QuarkIcons.notifications_outlined,
            size: 13,
            color: tokens.warning,
          ),
          Text(
            CalendarReminders.dueLabel(item, now),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: tokens.foreground,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: [
        item.title,
        if (item.allDay) 'all day' else span,
        if (item.location.isNotEmpty) item.location,
        if (item.repeat != CalendarRepeat.none)
          CalendarLabels.repeat(item.repeat, item.start),
        if (due)
          CalendarReminders.dueLabel(item, now)
        else if (reminder != null)
          'reminder $reminder',
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('calendar_upcoming_${item.key}'),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 16,
            vertical: compact ? 10 : 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: compact ? 10 : 14,
            children: [
              SizedBox(
                width: compact ? 58 : 72,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    when,
                    style: metaStyle.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(item.allDay ? 3 : 5),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: tokens.foreground,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                    if (due && compact) duePill,
                  ],
                ),
              ),
              if (due && !compact)
                duePill
              else if (reminder != null && !due)
                Tooltip(
                  message: reminder,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 5,
                    children: [
                      Icon(
                        QuarkIcons.notifications_outlined,
                        size: 15,
                        color: tokens.secondaryForeground,
                      ),
                      if (!compact) Text(reminder, style: metaStyle),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
