import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/calendar_event_item.dart';
import '../theme/quark_tokens.dart';
import 'calendar_dates.dart';
import 'calendar_labels.dart';

/// A due reminder, as a slim warning-tinted bar above the calendar: "Vet
/// starts at 4:00 PM · in 20 min", with Open and Dismiss.
///
/// Until phone alerts arrive (#1145) the calendar has no other way to say a
/// reminder is due while someone is looking at Month, Week or Day. Which
/// reminder is due, and whether it was dismissed, is the caller's to track.
///
/// Key prefixes: `calendar_reminder_<item.key>` on the bar,
/// `calendar_reminder_open_<item.key>` and
/// `calendar_reminder_dismiss_<item.key>` on its buttons.
///
/// ```dart
/// CalendarReminderBanner(
///   item: controller.dueReminder!,
///   now: now,
///   onOpen: () => edit(item.eventId),
///   onDismiss: () => controller.dismiss(item),
/// );
/// ```
class CalendarReminderBanner extends StatelessWidget {
  /// Creates the bar for [item], worded against [now].
  const CalendarReminderBanner({
    required this.item,
    required this.now,
    this.onOpen,
    this.onDismiss,
    super.key,
  });

  /// The occurrence whose reminder is due.
  final CalendarEventItem item;

  /// The current time.
  final DateTime now;

  /// Called by Open. Null hides it.
  final VoidCallback? onOpen;

  /// Called by Dismiss. Null hides it.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final String when;
    if (item.allDay) {
      final today = CalendarDates.dateOnly(now);
      when = CalendarDates.isSameDay(item.start, today)
          ? 'is today'
          : CalendarDates.isSameDay(item.start, CalendarDates.addDays(today, 1))
          ? 'is tomorrow'
          : 'is on ${CalendarLabels.dayTitleShort(item.start)}';
    } else {
      final at = CalendarLabels.time(item.start, use24Hour: use24Hour);
      final soon = CalendarLabels.startsIn(
        item.start.difference(now),
      ).replaceFirst('Starts in', 'in').replaceFirst('Starting now', 'now');
      when = CalendarDates.isSameDay(item.start, now)
          ? 'starts at $at · $soon'
          : 'starts ${CalendarLabels.dayTitleShort(item.start)} at $at';
    }

    return Container(
      key: ValueKey('calendar_reminder_${item.key}'),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tokens.warning.withValues(alpha: 0.1),
          tokens.card,
        ),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.4)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          spacing: tokens.spacingSm,
          children: [
            Icon(
              QuarkIcons.notifications_outlined,
              size: 18,
              color: tokens.warning,
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: item.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: ' $when'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: tokens.foreground),
              ),
            ),
            if (onOpen != null)
              TextButton(
                key: ValueKey('calendar_reminder_open_${item.key}'),
                onPressed: onOpen,
                child: const Text('Open'),
              ),
            if (onDismiss != null)
              TextButton(
                key: ValueKey('calendar_reminder_dismiss_${item.key}'),
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.secondaryForeground,
                ),
                child: const Text('Dismiss'),
              ),
          ],
        ),
      ),
    );
  }
}
