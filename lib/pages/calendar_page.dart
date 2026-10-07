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

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    _followRoute();
  }

  /// Shows the view, date and filter the route names; a missing or bad date
  /// is today, and no filter is everyone's events. Weeks start where the
  /// device's locale starts them (#2539).
  void _followRoute() {
    final query = GoRouterState.of(context).uri.queryParameters;
    final date =
        DateTime.tryParse(query[AppRoutes.calendarDateParam] ?? '') ??
        _calendar.today;
    final person = query[AppRoutes.calendarPersonParam];
    unawaited(
      _calendar.show(
        widget.view,
        date,
        mineOnly: query[AppRoutes.calendarMineParam] == 'true',
        person: person == null || person.isEmpty ? null : person,
        firstWeekday: firstWeekdayForLocale(
          View.of(context).platformDispatcher.locale,
        ),
      ),
    );
  }

  @override
  Future<void> refresh() => _calendar.refresh();

  /// Goes to [view] around [date], keeping the filter unless [mine] or
  /// [person] replaces it.
  ///
  /// The page shows it at once and the URL follows: the router asks the Quark
  /// whether the calendar is on before every calendar URL, and waiting for
  /// that round trip left the arrows a beat behind the click (#2888). When the
  /// route lands, [_followRoute] finds it already on show.
  void _go(
    CalendarView view,
    DateTime date, {
    bool? mine,
    String? person,
    bool everyone = false,
  }) {
    final mineOnly = everyone ? false : (mine ?? _calendar.mineOnly);
    final who = everyone || mine == true ? null : (person ?? _calendar.person);
    unawaited(_calendar.show(view, date, mineOnly: mineOnly, person: who));
    context.go(
      AppRoutes.calendarView(view, date: date, mine: mineOnly, person: who),
    );
  }

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
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: CalendarPersonFilter(
                  mine: _calendar.mineOnly,
                  person: _calendar.person,
                  people: _calendar.people,
                  onEveryone: () => _go(view, _calendar.anchor, everyone: true),
                  onMine: () => _go(view, _calendar.anchor, mine: true),
                  onPerson: (name) =>
                      _go(view, _calendar.anchor, mine: false, person: name),
                ),
              ),
              Expanded(
                child: CalendarBody(
                  view: view,
                  anchor: _calendar.anchor,
                  days: _calendar.days,
                  today: _calendar.today,
                  now: _calendar.now,
                  occurrences: _calendar.occurrences,
                  upcoming: _calendar.upcoming,
                  isInitialLoad: _calendar.isInitialLoad,
                  isLoading: _calendar.isLoading,
                  firstWeekday: _calendar.firstWeekday,
                  dueReminder: _calendar.dueReminder,
                  error: error == null
                      ? null
                      : Errors.message(error, 'load your calendar'),
                  onPrevious: () => _go(view, _calendar.previousAnchor),
                  onNext: () => _go(view, _calendar.nextAnchor),
                  onRetry: manualRefresh,
                  onDayTap: (day) => _go(CalendarView.day, day),
                  onCreateOn: (day) =>
                      _create(CalendarEventDraft.allDayOn(day)),
                  onCreateAt: (start) => _create(CalendarEventDraft.at(start)),
                  onEventTap: _edit,
                  onAddEvent: () => _create(_newDraft()),
                  onDismissReminder: _calendar.dismissReminder,
                ),
              ),
            ],
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
