import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/calendar_controller.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/router.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/calendar/calendar_bar_bottom.dart';
import 'package:quark/widgets/calendar/calendar_body.dart';
import 'package:quark/widgets/calendar/show_calendar_event_editor.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The household calendar (#1144): Day, Week, Month and Upcoming views of one
/// shared calendar, and the form that creates and edits its events.
///
/// The view is the route's (`/calendar/<view>`) and the date its `date` query,
/// so every step, switch and Today is a `context.go` and the address bar
/// always says what is on screen. [CalendarController] holds everything else.
class CalendarPage extends StatefulWidget {
  const CalendarPage({
    required this.view,
    required this.onViewSelected,
    super.key,
  });

  /// The view the route names.
  final CalendarView view;

  /// Switches the view, keeping the date; from `tabbedRoutes`.
  final ValueChanged<CalendarView> onViewSelected;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  final CalendarController _calendar = CalendarController()..startClock();
  StreamSubscription<FileEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = EventsService.instance.events.listen(
      (event) => _calendar.onServerEvent(event.kind),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followRoute();
  }

  @override
  void didUpdateWidget(CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followRoute();
  }

  @override
  void dispose() {
    _events?.cancel();
    _calendar.dispose();
    super.dispose();
  }

  /// Shows the view and date the route names; a missing or bad date is today.
  void _followRoute() {
    final param = GoRouterState.of(
      context,
    ).uri.queryParameters[AppRoutes.calendarDateParam];
    final date = DateTime.tryParse(param ?? '') ?? _calendar.today;
    unawaited(_calendar.show(widget.view, date));
  }

  @override
  Future<void> refresh() => _calendar.refresh();

  void _go(CalendarView view, DateTime date) =>
      context.go(AppRoutes.calendarView(view, date: date));

  Future<void> _edit(CalendarEventItem item) {
    final event = _calendar.eventById(item.eventId);
    if (event == null) return Future.value();
    return showCalendarEventEditor(
      context,
      calendar: _calendar,
      draft: event.toDraft(),
      eventId: event.id,
    );
  }

  Future<void> _create(CalendarEventDraft draft) =>
      showCalendarEventEditor(context, calendar: _calendar, draft: draft);

  /// A new event from the bar's button: the next whole hour when the view is
  /// on today, 9 AM on the date on show otherwise.
  CalendarEventDraft _newDraft() {
    final anchor = _calendar.anchor;
    final now = _calendar.now;
    if (CalendarDates.isSameDay(anchor, now) ||
        _calendar.view == CalendarView.upcoming) {
      return CalendarEventDraft.at(
        DateTime(now.year, now.month, now.day, now.hour + 1),
      );
    }
    return CalendarEventDraft.at(
      DateTime(anchor.year, anchor.month, anchor.day, 9),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _calendar,
      builder: (context, _) {
        final view = _calendar.view;
        final error = _calendar.error;
        return QuarkPageScaffold(
          title: 'Calendar',
          icon: QuarkIcons.calendar_month_outlined,
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.calendar),
          body: CalendarBody(
            view: view,
            anchor: _calendar.anchor,
            days: _calendar.days,
            today: _calendar.today,
            now: _calendar.now,
            occurrences: _calendar.occurrences,
            upcoming: _calendar.upcoming,
            isInitialLoad: _calendar.isInitialLoad,
            dueReminder: _calendar.dueReminder,
            error: error == null
                ? null
                : Errors.message(error, 'load your calendar'),
            onPrevious: () => _go(view, _calendar.previousAnchor),
            onNext: () => _go(view, _calendar.nextAnchor),
            onRetry: manualRefresh,
            onDayTap: (day) => _go(CalendarView.day, day),
            onCreateOn: (day) => _create(CalendarEventDraft.allDayOn(day)),
            onCreateAt: (start) => _create(CalendarEventDraft.at(start)),
            onEventTap: _edit,
            onAddEvent: () => _create(_newDraft()),
            onDismissReminder: _calendar.dismissReminder,
          ),
          appBar: QuarkAppBar(
            label: 'Calendar',
            icon: QuarkIcons.calendar_month_outlined,
            onRefresh: manualRefresh,
            isRefreshing: isRefreshing,
            actions: [
              QuarkBarChip(
                key: const ValueKey('calendar_new_event'),
                icon: QuarkIcons.add_rounded,
                label: 'New event',
                onPressed: () => _create(_newDraft()),
              ),
            ],
            bottom: CalendarBarBottom(
              view: view,
              anchor: _calendar.anchor,
              days: _calendar.days,
              onPrevious: () => _go(view, _calendar.previousAnchor),
              onNext: () => _go(view, _calendar.nextAnchor),
              onToday: () => _go(view, _calendar.today),
              onViewSelected: widget.onViewSelected,
            ),
          ),
        );
      },
    );
  }
}
