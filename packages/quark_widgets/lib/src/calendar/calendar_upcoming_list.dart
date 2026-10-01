import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/calendar_day_events.dart';
import '../models/calendar_event_item.dart';
import '../theme/quark_tokens.dart';
import 'calendar_upcoming_list/upcoming_day_header.dart';
import 'calendar_upcoming_list/upcoming_event_row.dart';

/// The next few days as a list grouped by date: the calendar's Upcoming view,
/// and in the MVP the one place reminders show.
///
/// Each date is headed "Today", "Tomorrow" or its weekday, over a card of its
/// events. An event whose reminder is due at [now] says how soon it starts.
/// Loading, error and empty are inputs. The spinner and the error text stand
/// in for the list only while [days] holds nothing; with events on screen, the
/// error sits above them. Empty offers [onAddEvent].
///
/// Key prefixes: `calendar_upcoming_<item.key>` on each row, and
/// `calendar_upcoming_add` on the empty state's button.
///
/// ```dart
/// CalendarUpcomingList(
///   days: controller.upcoming,
///   today: today,
///   now: now,
///   isLoading: controller.isLoading,
///   error: controller.error,
///   onEventTap: (item) => edit(item.eventId),
///   onAddEvent: createNew,
/// );
/// ```
class CalendarUpcomingList extends StatelessWidget {
  /// Creates the list of [days].
  const CalendarUpcomingList({
    required this.days,
    required this.today,
    required this.now,
    this.isLoading = false,
    this.error,
    this.onEventTap,
    this.onAddEvent,
    super.key,
  });

  /// The dates to list, in order. Dates without events are skipped.
  final List<CalendarDayEvents> days;

  /// Today's date, which names the first headings.
  final DateTime today;

  /// The current time, which decides which reminders are due.
  final DateTime now;

  /// Whether events are being fetched. Shows a loader while there are none.
  final bool isLoading;

  /// A sentence the caller composed about a failed fetch, or null.
  final String? error;

  /// Called with the event whose row was tapped.
  final ValueChanged<CalendarEventItem>? onEventTap;

  /// Called by the empty state's "Add an event". Null hides the button.
  final VoidCallback? onAddEvent;

  /// Below this width the list runs edge to edge in the phone layout.
  static const double compactWidth = 600;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final groups = [
      for (final day in days)
        if (day.events.isNotEmpty) day,
    ];
    final errorText = error == null
        ? null
        : Padding(
            padding: EdgeInsets.all(tokens.spacingMd),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.error),
            ),
          );

    if (groups.isEmpty) {
      if (isLoading) return const Center(child: QuarkLoader());
      if (errorText != null) return Center(child: errorText);
      return EmptyStateWidget(
        icon: QuarkIcons.view_agenda_outlined,
        headline: 'Nothing in the next 7 days',
        subtext:
            'Events you add show up here, along with any reminders you set.',
        action: onAddEvent == null
            ? null
            : FilledButton.icon(
                key: const ValueKey('calendar_upcoming_add'),
                onPressed: onAddEvent,
                icon: const Icon(QuarkIcons.add_rounded, size: 18),
                label: const Text('Add an event'),
              ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactWidth;
        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: compact
                ? 0
                : ((constraints.maxWidth - 760) / 2).clamp(
                    tokens.spacingMd,
                    double.infinity,
                  ),
            vertical: compact ? 0 : tokens.spacingLg,
          ),
          children: [
            ?errorText,
            for (final group in groups) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 4,
                  compact ? 14 : 0,
                  16,
                  compact ? 6 : 8,
                ),
                child: UpcomingDayHeader(day: group.day, today: today),
              ),
              Container(
                margin: EdgeInsets.only(bottom: compact ? 0 : 20),
                decoration: BoxDecoration(
                  color: tokens.card,
                  borderRadius: compact
                      ? null
                      : BorderRadius.circular(tokens.radiusLg),
                  border: compact
                      ? Border.symmetric(
                          horizontal: BorderSide(color: tokens.border),
                        )
                      : Border.all(color: tokens.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (index, item) in group.events.indexed) ...[
                      if (index > 0) Divider(height: 1, color: tokens.border),
                      UpcomingEventRow(
                        item: item,
                        now: now,
                        compact: compact,
                        onTap: onEventTap == null
                            ? null
                            : () => onEventTap!(item),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
