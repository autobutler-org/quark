import 'package:flutter/material.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/widgets/calendar/calendar_swipe_detector.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the Calendar page's bars: the view on show, a due
/// reminder above it, and the loading and error states around it.
///
/// On Day, Week and Month a horizontal swipe steps one span back or forward,
/// the phone's stand-in for the arrows; see [CalendarSwipeDetector]. Upcoming shows due reminders in its
/// own rows, so it has no reminder bar.
///
/// A load that fails before anything has shown fills the body with a retry;
/// one that fails later keeps the last view on show under an [ErrorBanner]
/// with its own Try again (#2540).
///
/// Month rows start on [firstWeekday], the same weekday the page loaded the
/// span with (#2539). An empty Month or Day says so over its grid and offers
/// [onAddEvent], but not while [isLoading], when an empty span only means the
/// new one has not arrived yet (#2538).
///
/// Key prefixes: `calendar_retry` on the first load's retry button,
/// `calendar_error_retry` on a later failed load's, and the keys of the
/// package widget on show.
class CalendarBody extends StatelessWidget {
  /// Creates the body for [view].
  const CalendarBody({
    required this.view,
    required this.anchor,
    required this.days,
    required this.today,
    required this.now,
    required this.occurrences,
    required this.upcoming,
    required this.isInitialLoad,
    required this.isLoading,
    required this.firstWeekday,
    required this.onPrevious,
    required this.onNext,
    required this.onRetry,
    required this.onDayTap,
    required this.onCreateOn,
    required this.onCreateAt,
    required this.onEventTap,
    required this.onAddEvent,
    this.dueReminder,
    this.onDismissReminder,
    this.error,
    super.key,
  });

  final CalendarView view;
  final DateTime anchor;

  /// The dates the view spans.
  final List<DateTime> days;
  final DateTime today;
  final DateTime now;

  /// The occurrences in [days].
  final List<CalendarEventItem> occurrences;

  /// The next seven days, for Upcoming.
  final List<CalendarDayEvents> upcoming;

  /// Whether nothing has loaded yet.
  final bool isInitialLoad;

  /// Whether a load is in flight, which holds back the empty states.
  final bool isLoading;

  /// The weekday month rows start on.
  final int firstWeekday;

  /// The reminder to show above the view, or null.
  final CalendarEventItem? dueReminder;

  /// The page's sentence about a failed load, or null.
  final String? error;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  /// Opens a date in Day view.
  final ValueChanged<DateTime> onDayTap;

  /// Creates an all-day event on a date: a month cell's long press or add.
  final ValueChanged<DateTime> onCreateOn;

  /// Creates a timed event from an hour: an empty slot's tap.
  final ValueChanged<DateTime> onCreateAt;

  /// Opens an event in the form.
  final ValueChanged<CalendarEventItem> onEventTap;

  /// Creates an event from an empty Month, Day or Upcoming.
  final VoidCallback onAddEvent;

  /// Hides [dueReminder].
  final ValueChanged<CalendarEventItem>? onDismissReminder;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    if (isInitialLoad && view != CalendarView.upcoming) {
      if (error != null) {
        return EmptyStateWidget(
          icon: QuarkIcons.error_outline,
          headline: "Couldn't load your calendar",
          subtext: error,
          action: FilledButton(
            key: const ValueKey('calendar_retry'),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        );
      }
      return const Center(child: QuarkLoader());
    }

    final Widget content = switch (view) {
      CalendarView.month => CalendarMonthGrid(
        month: anchor,
        today: today,
        selectedDay: CalendarDates.isSameDay(anchor, today) ? today : null,
        events: occurrences,
        firstWeekday: firstWeekday,
        isLoading: isLoading,
        onDayTap: onDayTap,
        onDayLongPress: onCreateOn,
        onAddTap: onCreateOn,
        onEventTap: onEventTap,
        onAddEvent: onAddEvent,
      ),
      // One timeline across steps, so a new span keeps the hours on show
      // rather than scrolling back to the morning (#2887).
      CalendarView.week || CalendarView.day => CalendarTimeGrid(
        days: days,
        today: today,
        now: now,
        events: occurrences,
        isLoading: isLoading,
        onSlotTap: onCreateAt,
        onEventTap: onEventTap,
        onDayTap: onDayTap,
        onAddEvent: onAddEvent,
      ),
      CalendarView.upcoming => CalendarUpcomingList(
        days: upcoming,
        today: today,
        now: now,
        isLoading: isInitialLoad,
        error: error,
        onEventTap: onEventTap,
        onAddEvent: onAddEvent,
      ),
    };

    final reminder = dueReminder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reminder != null && view != CalendarView.upcoming)
          Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: CalendarReminderBanner(
              item: reminder,
              now: now,
              onOpen: () => onEventTap(reminder),
              onDismiss: onDismissReminder == null
                  ? null
                  : () => onDismissReminder!(reminder),
            ),
          ),
        if (error != null && view != CalendarView.upcoming)
          Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: Row(
              children: [
                Expanded(child: ErrorBanner(message: error)),
                SizedBox(width: tokens.spacingSm),
                FilledButton(
                  key: const ValueKey('calendar_error_retry'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        Expanded(
          child: view == CalendarView.upcoming
              ? content
              : CalendarSwipeDetector(
                  onPrevious: onPrevious,
                  onNext: onNext,
                  child: content,
                ),
        ),
      ],
    );
  }
}
