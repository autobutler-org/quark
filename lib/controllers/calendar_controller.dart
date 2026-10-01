import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/calendar_event.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/services/calendar_service.dart';
import 'package:quark/utils/calendar_recurrence.dart';
import 'package:quark_widgets/quark_widgets.dart';

typedef ListCalendarEventsFn =
    Future<List<CalendarEvent>> Function(DateTime from, DateTime to);
typedef SaveCalendarEventFn =
    Future<CalendarEvent> Function(CalendarEventDraft draft, {int? id});
typedef DeleteCalendarEventFn = Future<void> Function(int id);

/// State behind the Calendar page (#1144): which view and date are on show,
/// the events in that span expanded into occurrences, the next seven days for
/// Upcoming, and which reminder is due.
///
/// Two ranges load independently: the one the view shows, and the next seven
/// days from today. The second feeds both Upcoming and the reminder bar, so a
/// due reminder shows whichever month is on screen. Saving or deleting reloads
/// both but never moves the view (#320): an event made in November leaves
/// November on screen.
class CalendarController extends ChangeNotifier {
  CalendarController({
    this.listEvents = CalendarService.listEvents,
    this.saveEvent = CalendarService.saveEvent,
    this.deleteEvent = CalendarService.deleteEvent,
    this.clock = DateTime.now,
    this.firstWeekday = DateTime.sunday,
  }) : _anchor = CalendarDates.dateOnly(clock()),
       _now = clock();

  final ListCalendarEventsFn listEvents;
  final SaveCalendarEventFn saveEvent;
  final DeleteCalendarEventFn deleteEvent;
  final DateTime Function() clock;

  /// The weekday a week and a month row start on.
  final int firstWeekday;

  /// How many days Upcoming covers, today included.
  static const int upcomingDays = 7;

  CalendarView _view = CalendarView.week;
  DateTime _anchor;
  DateTime _now;
  Timer? _ticker;

  List<CalendarEvent> _viewEvents = const [];
  List<CalendarEvent> _upcomingEvents = const [];
  bool _viewLoaded = false;
  bool _isLoading = false;
  Object? _error;
  int _generation = 0;
  final Set<String> _dismissed = {};
  bool _disposed = false;

  /// The view on show.
  CalendarView get view => _view;

  /// The date the view is built around: the day for Day, any date in the
  /// week or month otherwise.
  DateTime get anchor => _anchor;

  /// The current time, advanced every minute while [startClock] runs.
  DateTime get now => _now;

  /// Today's date.
  DateTime get today => CalendarDates.dateOnly(_now);

  /// Whether a load is in flight.
  bool get isLoading => _isLoading;

  /// Whether nothing has loaded yet for the view on show.
  bool get isInitialLoad => !_viewLoaded;

  /// Why the last load failed, or null. The page words it with `Errors`.
  Object? get error => _error;

  /// The dates the view spans: one for Day, a week, the month grid's whole
  /// weeks, or the days of Upcoming.
  List<DateTime> get days => switch (_view) {
    CalendarView.day => [_anchor],
    CalendarView.week => CalendarDates.weekOf(
      _anchor,
      firstWeekday: firstWeekday,
    ),
    CalendarView.month => CalendarDates.monthGrid(
      _anchor,
      firstWeekday: firstWeekday,
    ),
    CalendarView.upcoming => [
      for (var i = 0; i < upcomingDays; i++) CalendarDates.addDays(today, i),
    ],
  };

  /// The occurrences in the view's span.
  List<CalendarEventItem> get occurrences {
    final span = days;
    return expandOccurrences(
      _viewEvents,
      span.first,
      CalendarDates.addDays(span.last, 1),
    );
  }

  /// The next [upcomingDays] days from now, each with its occurrences.
  /// Timed events already over today are left out.
  List<CalendarDayEvents> get upcoming {
    final items = _upcomingItems();
    return [
      for (var i = 0; i < upcomingDays; i++)
        CalendarDayEvents(
          day: CalendarDates.addDays(today, i),
          events:
              [
                for (final item in items)
                  if (item.dates.any(
                    (d) => CalendarDates.isSameDay(
                      d,
                      CalendarDates.addDays(today, i),
                    ),
                  ))
                    item,
              ]..sort(
                (a, b) => a.allDay == b.allDay
                    ? a.start.compareTo(b.start)
                    : (a.allDay ? -1 : 1),
              ),
        ),
    ];
  }

  /// The soonest reminder that is due and not dismissed, or null.
  CalendarEventItem? get dueReminder {
    for (final item in _upcomingItems()) {
      if (_dismissed.contains(item.key)) continue;
      if (CalendarReminders.isDue(item, _now)) return item;
    }
    return null;
  }

  List<CalendarEventItem> _upcomingItems() => [
    for (final item in expandOccurrences(
      _upcomingEvents,
      today,
      CalendarDates.addDays(today, upcomingDays),
    ))
      if (item.allDay || item.end.isAfter(_now)) item,
  ];

  /// The stored event [id], from whichever range holds it.
  CalendarEvent? eventById(int id) {
    for (final event in [..._viewEvents, ..._upcomingEvents]) {
      if (event.id == id) return event;
    }
    return null;
  }

  /// The date one span before [anchor]: a day, a week or a month back.
  DateTime get previousAnchor => _step(-1);

  /// The date one span after [anchor].
  DateTime get nextAnchor => _step(1);

  DateTime _step(int direction) => switch (_view) {
    CalendarView.day => CalendarDates.addDays(_anchor, direction),
    CalendarView.week => CalendarDates.addDays(_anchor, 7 * direction),
    // The 1st, so stepping from the 31st never skips a short month.
    CalendarView.month => DateTime(_anchor.year, _anchor.month + direction),
    CalendarView.upcoming => _anchor,
  };

  /// Shows [view] around [anchor], loading its span when it changed.
  Future<void> show(CalendarView view, DateTime anchor) async {
    final date = CalendarDates.dateOnly(anchor);
    final before = days;
    _view = view;
    _anchor = date;
    final after = days;
    final sameSpan =
        _viewLoaded && before.first == after.first && before.last == after.last;
    notifyListeners();
    if (!sameSpan) await _loadView();
  }

  /// Loads the view's span and the upcoming days again.
  Future<void> refresh() async {
    _now = clock();
    await Future.wait([_loadView(), _loadUpcoming()]);
  }

  Future<void> _loadView() async {
    final generation = ++_generation;
    final span = days;
    _isLoading = true;
    notifyListeners();
    try {
      final events = await listEvents(
        span.first,
        CalendarDates.addDays(span.last, 1),
      );
      if (generation != _generation) return;
      _viewEvents = events;
      _viewLoaded = true;
      _error = null;
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadUpcoming() async {
    try {
      _upcomingEvents = await listEvents(
        today,
        CalendarDates.addDays(today, upcomingDays),
      );
      notifyListeners();
    } catch (_) {
      // The view's own load reports the failure; Upcoming keeps what it had.
    }
  }

  /// Saves [draft] as a new event, or over event [id], then reloads without
  /// moving the view. Throws what the save threw, for the editor to word.
  Future<void> save(CalendarEventDraft draft, {int? id}) async {
    await saveEvent(draft, id: id);
    await refresh();
  }

  /// Deletes event [id] and reloads. Throws what the delete threw.
  Future<void> delete(int id) async {
    await deleteEvent(id);
    await refresh();
  }

  /// Answers an event from `/api/v0/events`: another client changed the
  /// calendar, so reload.
  void onServerEvent(String kind) {
    if (kind == 'calendar_changed') unawaited(refresh());
  }

  /// Hides [item]'s reminder bar until the app restarts.
  void dismissReminder(CalendarEventItem item) {
    _dismissed.add(item.key);
    notifyListeners();
  }

  /// Starts advancing [now] every minute, so the now line and due reminders
  /// keep up with the clock.
  void startClock({Duration every = const Duration(minutes: 1)}) {
    _ticker ??= Timer.periodic(every, (_) {
      _now = clock();
      notifyListeners();
    });
  }

  // A load that finishes after the page has gone must not notify it.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
