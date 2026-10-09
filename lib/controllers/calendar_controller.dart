import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:quark/models/calendar_event.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/models/user_account.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/calendar_service.dart';
import 'package:quark/services/users_service.dart';
import 'package:quark/utils/calendar_recurrence.dart';
import 'package:quark_widgets/quark_widgets.dart';

typedef ListCalendarEventsFn =
    Future<List<CalendarEvent>> Function(DateTime from, DateTime to);
typedef SaveCalendarEventFn =
    Future<CalendarEvent> Function(CalendarEventDraft draft, {int? id});
typedef DeleteCalendarEventFn = Future<void> Function(int id);
typedef ListCalendarPeopleFn = Future<List<String>> Function();

/// The usernames of the Quark's active accounts, alphabetically: whom an
/// admin can narrow the calendar to. Only admins may list accounts.
Future<List<String>> listCalendarPeople() async => [
  for (final account in await UsersService.list())
    if (account.status == UserAccount.active) account.username,
]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

/// The weekday [locale]'s weeks start on (#2539): what Flutter's
/// `MaterialLocalizations.firstDayOfWeekIndex` says for it, so Sunday for
/// en-US, Monday for de-DE or en-GB, Saturday for fa-IR.
///
/// The app's own localizations resolve every device to plain English, which
/// would make every week start on Sunday, so this asks about the device's
/// locale directly. A language Flutter has no localizations for gets
/// `CalendarDates.defaultFirstWeekday`, Sunday.
int firstWeekdayForLocale(Locale locale) {
  // Language and region only: they decide the week, and the delegate rejects
  // a script code in a form intl does not use.
  final plain = Locale(locale.languageCode, locale.countryCode);
  const delegate = GlobalMaterialLocalizations.delegate;
  if (!delegate.isSupported(plain)) return CalendarDates.defaultFirstWeekday;
  int? index;
  // Material's delegate answers with a SynchronousFuture, so `then` runs
  // before this returns.
  unawaited(delegate.load(plain).then((l) => index = l.firstDayOfWeekIndex));
  return CalendarDates.firstWeekdayFromIndex(index);
}

/// State behind the Calendar page (#1144): which view and date are on show,
/// the events in that span expanded into occurrences, the next seven days for
/// Upcoming, and which reminder is due.
///
/// Two ranges load independently: the one the view shows, and the next seven
/// days from today. The second feeds both Upcoming and the reminder bar, so a
/// due reminder shows whichever month is on screen. Saving or deleting reloads
/// both but never moves the view (#320): an event made in November leaves
/// November on screen.
///
/// A drag or a key press on the timeline goes through [reschedule] (#2526),
/// which shows the event at its new times at once and saves behind that, so
/// the event does not jump back while the save is on its way.
///
/// It can narrow everything it shows to one person's events (#2544): the
/// signed-in person's with [mineOnly], or a named person's with [person],
/// which an admin picks from [people]. The calendar stays shared, so this is
/// a filter over what every account can see anyway.
///
/// Weeks and month rows start on [firstWeekday], which the page sets from the
/// device locale through [show]; the span it loads and the grid it draws both
/// come from [days], so they always agree (#2539).
class CalendarController extends ChangeNotifier {
  CalendarController({
    this.listEvents = CalendarService.listEvents,
    this.saveEvent = CalendarService.saveEvent,
    this.deleteEvent = CalendarService.deleteEvent,
    this.listPeople = listCalendarPeople,
    this.canListPeople = _isAdmin,
    this.clock = DateTime.now,
    int firstWeekday = CalendarDates.defaultFirstWeekday,
  }) : _firstWeekday = firstWeekday,
       _anchor = CalendarDates.dateOnly(clock()),
       _now = clock();

  final ListCalendarEventsFn listEvents;
  final SaveCalendarEventFn saveEvent;
  final DeleteCalendarEventFn deleteEvent;

  /// Lists the people an admin can narrow the calendar to.
  final ListCalendarPeopleFn listPeople;

  /// Whether the signed-in account may list people, which is an admin's.
  final bool Function() canListPeople;
  final DateTime Function() clock;

  static bool _isAdmin() => AppSettings.instance.isAdmin.value;

  int _firstWeekday;

  /// The weekday a week and a month row start on.
  int get firstWeekday => _firstWeekday;

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
  bool _mineOnly = false;
  String? _person;
  List<String> _people = const [];

  // Events [reschedule] has moved whose save and reload have not come back,
  // by id: what the views show in place of the loaded event until they do.
  final Map<int, CalendarEvent> _moved = {};

  // The last save [reschedule] queued, so the next one waits its turn.
  Future<void> _saves = Future.value();

  /// Whether only the signed-in person's events are shown.
  bool get mineOnly => _mineOnly;

  /// The one person whose events are shown, or null. Unused while [mineOnly].
  String? get person => _mineOnly ? null : _person;

  /// Whom the person filter offers: the active accounts for an admin, and
  /// nobody for anyone else.
  List<String> get people => _people;

  /// Whether [event] passes the filter.
  bool _shows(CalendarEvent event) {
    if (_mineOnly) return event.mine;
    final person = _person;
    return person == null || event.owner == person;
  }

  /// The events of [events] to show: those passing the filter, each where
  /// [reschedule] last moved it.
  Iterable<CalendarEvent> _shown(List<CalendarEvent> events) =>
      events.where(_shows).map((event) => _moved[event.id] ?? event);

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
      _shown(_viewEvents),
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
      _shown(_upcomingEvents),
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

  /// Shows [view] around [anchor], narrowed to the signed-in person's events
  /// with [mineOnly] or to [person]'s, with weeks starting on [firstWeekday]
  /// when given, loading its span when it changed. Changing only the filter
  /// loads nothing: it narrows what is loaded.
  Future<void> show(
    CalendarView view,
    DateTime anchor, {
    bool mineOnly = false,
    String? person,
    int? firstWeekday,
  }) async {
    final date = CalendarDates.dateOnly(anchor);
    final before = days;
    _view = view;
    _anchor = date;
    _firstWeekday = firstWeekday ?? _firstWeekday;
    _mineOnly = mineOnly;
    _person = person;
    final after = days;
    final sameSpan =
        _viewLoaded && before.first == after.first && before.last == after.last;
    notifyListeners();
    if (!sameSpan) await _loadView();
  }

  /// Loads the view's span and the upcoming days again.
  Future<void> refresh() async {
    _now = clock();
    await Future.wait([_loadView(), _loadUpcoming(), _loadPeople()]);
  }

  Future<void> _loadPeople() async {
    if (!canListPeople()) {
      _people = const [];
      return;
    }
    try {
      _people = await listPeople();
      notifyListeners();
    } catch (_) {
      // Without the list the person chip is hidden; Everyone and My events
      // still work.
      _people = const [];
    }
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

  /// Moves the occurrence [item] to run from [start] to [end]: a drag or a
  /// key press on the timeline (#2526).
  ///
  /// The stored event moves as far as the occurrence did, as many dates and
  /// to the same times of day, so a repeating event moves as a whole series,
  /// as it does from the editor. The views show the move at once. The save
  /// follows, after any move asked before it so the last one asked is the
  /// last one saved, and the reload after the save. Throws what the save
  /// threw, with the event back where the Quark has it.
  Future<void> reschedule(
    CalendarEventItem item,
    DateTime start,
    DateTime end,
  ) async {
    final event = _moved[item.eventId] ?? eventById(item.eventId);
    if (event == null) return;
    final draft = event.toDraft();
    final moved = draft.copyWith(
      start: _carried(draft.start, item.start, start),
      end: _carried(draft.end, item.end, end),
    );
    final shown = event.movedTo(moved.start, moved.end);
    _moved[event.id] = shown;
    notifyListeners();
    final save = _saves.then((_) => saveEvent(moved, id: event.id));
    _saves = save.then((_) {}, onError: (_) {});
    try {
      await save;
    } finally {
      // A later move of the same event shows until its own save is back.
      if (identical(_moved[event.id], shown)) {
        await refresh();
        if (identical(_moved[event.id], shown)) _moved.remove(event.id);
        notifyListeners();
      }
    }
  }

  /// [time] carried as far as an occurrence went [from] one time [to]
  /// another: as many dates on, at [to]'s time of day. Dates are counted in
  /// UTC, where no day is an hour short.
  static DateTime _carried(DateTime time, DateTime from, DateTime to) {
    final dates = DateTime.utc(
      to.year,
      to.month,
      to.day,
    ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
    return DateTime(
      time.year,
      time.month,
      time.day + dates,
      to.hour,
      to.minute,
    );
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
