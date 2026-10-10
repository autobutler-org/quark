import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/calendar_controller.dart';
import 'package:quark/models/calendar_event.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Calendar page's state: spans, loads, upcoming days, due reminders, and
/// the #320 regression.
final _now = DateTime(2026, 9, 29, 15, 40);

CalendarEvent _event(
  int id,
  DateTime localStart,
  Duration length, {
  CalendarRepeat repeat = CalendarRepeat.none,
  int? reminder,
  String owner = '',
  bool mine = false,
}) => CalendarEvent(
  id: id,
  title: 'Event $id',
  start: localStart.toUtc(),
  end: localStart.add(length).toUtc(),
  repeat: repeat,
  reminderMinutes: reminder,
  owner: owner,
  mine: mine,
);

class _Server {
  _Server(this.events);

  List<CalendarEvent> events;
  final ranges = <(DateTime, DateTime)>[];
  final saved = <(CalendarEventDraft, int?)>[];
  final deleted = <int>[];
  Object? failWith;

  Future<List<CalendarEvent>> list(DateTime from, DateTime to) async {
    ranges.add((from, to));
    if (failWith != null) throw failWith!;
    return [
      for (final e in events)
        if (e.repeat != CalendarRepeat.none ||
            (e.localEnd.isAfter(from) && e.localStart.isBefore(to)))
          e,
    ];
  }

  Future<CalendarEvent> save(CalendarEventDraft draft, {int? id}) async {
    saved.add((draft, id));
    return _event(99, draft.start, draft.end.difference(draft.start));
  }

  Future<void> delete(int id) async => deleted.add(id);

  CalendarController controller({bool admin = false}) => CalendarController(
    listEvents: list,
    saveEvent: save,
    deleteEvent: delete,
    listPeople: () async => ['maya', 'sam'],
    canListPeople: () => admin,
    clock: () => _now,
  );
}

void main() {
  final vet = _event(
    14,
    DateTime(2026, 9, 29, 16),
    const Duration(minutes: 45),
    reminder: 30,
  );
  final soccer = _event(
    7,
    DateTime(2026, 9, 3, 17, 30),
    const Duration(minutes: 90),
    repeat: CalendarRepeat.weekly,
  );

  test('opens on the week holding today', () {
    final c = _Server([]).controller();
    expect(c.view, CalendarView.week);
    expect(c.days.first, DateTime(2026, 9, 27));
    expect(c.days.last, DateTime(2026, 10, 3));
    expect(c.isInitialLoad, isTrue);
  });

  test('loads the view span and the next seven days', () async {
    final server = _Server([vet, soccer]);
    final c = server.controller();
    await c.show(CalendarView.month, DateTime(2026, 9, 17));
    await c.refresh();

    expect(
      server.ranges,
      contains((DateTime(2026, 8, 30), DateTime(2026, 10, 4))),
    );
    expect(
      server.ranges,
      contains((DateTime(2026, 9, 29), DateTime(2026, 10, 6))),
    );
    expect(c.isInitialLoad, isFalse);
    expect(c.error, isNull);
  });

  test('the weekly preset shows on the right days of the month', () async {
    final c = _Server([soccer]).controller();
    await c.show(CalendarView.month, DateTime(2026, 9));
    expect(c.occurrences.map((o) => CalendarDates.key(o.start)), [
      '2026-09-03',
      '2026-09-10',
      '2026-09-17',
      '2026-09-24',
      '2026-10-01',
    ]);
  });

  test('moving within the same span does not load again', () async {
    final server = _Server([]);
    final c = server.controller();
    await c.show(CalendarView.week, DateTime(2026, 9, 28));
    final loads = server.ranges.length;
    await c.show(CalendarView.week, DateTime(2026, 10, 1));
    expect(server.ranges, hasLength(loads));
    await c.show(CalendarView.week, DateTime(2026, 10, 5));
    expect(server.ranges, hasLength(loads + 1));
  });

  test('steps by the view: a day, a week, a month from the 1st', () async {
    final c = _Server([]).controller();
    await c.show(CalendarView.day, DateTime(2026, 9, 29));
    expect(c.nextAnchor, DateTime(2026, 9, 30));
    await c.show(CalendarView.week, DateTime(2026, 9, 29));
    expect(c.previousAnchor, DateTime(2026, 9, 22));
    await c.show(CalendarView.month, DateTime(2026, 1, 31));
    expect(c.nextAnchor, DateTime(2026, 2));
  });

  test(
    'saving an event in another month keeps that month on screen (#320)',
    () async {
      final server = _Server([]);
      final c = server.controller();
      await c.show(CalendarView.month, DateTime(2026, 11, 12));

      await c.save(
        CalendarEventDraft.at(
          DateTime(2026, 11, 20, 10),
        ).copyWith(title: 'Dentist'),
      );

      expect(server.saved.single.$2, isNull);
      expect(c.view, CalendarView.month);
      expect(c.anchor, DateTime(2026, 11, 12));
      // The reload after the save asked for November again, not today's month.
      expect(
        server.ranges.where(
          (r) => r == (DateTime(2026, 11, 1), DateTime(2026, 12, 6)),
        ),
        hasLength(2),
      );
      expect(c.days.first, DateTime(2026, 11, 1));
    },
  );

  test('deleting reloads without moving', () async {
    final server = _Server([vet]);
    final c = server.controller();
    await c.show(CalendarView.day, DateTime(2026, 10, 7));
    await c.delete(14);
    expect(server.deleted, [14]);
    expect(c.anchor, DateTime(2026, 10, 7));
  });

  test('upcoming lists the next seven days, dropping what is over', () async {
    final lunch = _event(
      13,
      DateTime(2026, 9, 29, 12, 30),
      const Duration(hours: 1),
    );
    final c = _Server([vet, lunch, soccer]).controller();
    await c.refresh();

    final days = c.upcoming;
    expect(days, hasLength(7));
    expect(days.first.day, DateTime(2026, 9, 29));
    expect(days.first.events.map((e) => e.eventId), [14]);
    expect(days[2].events.map((e) => e.eventId), [7]);
  });

  test('a due reminder shows until dismissed', () async {
    final c = _Server([vet]).controller();
    await c.refresh();
    final due = c.dueReminder;
    expect(due?.eventId, 14);
    c.dismissReminder(due!);
    expect(c.dueReminder, isNull);
  });

  test('a failed load keeps the error for the page to word', () async {
    final server = _Server([])..failWith = ApiException(500, 'load');
    final c = server.controller();
    await c.show(CalendarView.week, DateTime(2026, 9, 29));
    expect(c.error, isA<ApiException>());
    expect(c.isLoading, isFalse);
  });

  // #2540: a failed refresh after a load keeps what was on show, so the page
  // can show it under the error, and a retry that works clears the error.
  test('a later failed load keeps the events, and a retry clears it', () async {
    final server = _Server([vet]);
    final c = server.controller();
    await c.refresh();
    expect(c.occurrences.map((e) => e.eventId), [14]);

    server.failWith = ApiException(500, 'load');
    await c.refresh();
    expect(c.error, isA<ApiException>());
    expect(c.isInitialLoad, isFalse);
    expect(c.occurrences.map((e) => e.eventId), [14]);
    expect(c.upcoming.first.events.map((e) => e.eventId), [14]);

    server.failWith = null;
    await c.refresh();
    expect(c.error, isNull);
    expect(c.occurrences.map((e) => e.eventId), [14]);
  });

  test('another client changing the calendar reloads it', () async {
    final server = _Server([]);
    final c = server.controller();
    await c.refresh();
    final loads = server.ranges.length;
    c.onServerEvent('upload');
    c.onServerEvent('calendar_changed');
    await Future<void>.delayed(Duration.zero);
    expect(server.ranges.length, loads + 2);
  });

  test('finds an event by id in either range', () async {
    final c = _Server([vet]).controller();
    await c.refresh();
    expect(c.eventById(14)?.title, 'Event 14');
    expect(c.eventById(1), isNull);
  });

  group('reschedule (#2526)', () {
    late _Server server;
    // One per save the controller has started; completing it lets the save
    // through, and failing it fails the save.
    late List<Completer<void>> gates;

    CalendarController held() => CalendarController(
      listEvents: server.list,
      saveEvent: (draft, {id}) async {
        final gate = Completer<void>();
        gates.add(gate);
        server.saved.add((draft, id));
        await gate.future;
        final saved = server.events
            .firstWhere((e) => e.id == id)
            .movedTo(draft.start, draft.end);
        server.events = [for (final e in server.events) e.id == id ? saved : e];
        return saved;
      },
      deleteEvent: server.delete,
      canListPeople: () => false,
      clock: () => _now,
    );

    CalendarEventItem shown(CalendarController calendar, int id) =>
        calendar.occurrences.singleWhere((o) => o.eventId == id);

    setUp(() {
      server = _Server([vet, soccer]);
      gates = [];
    });

    test("shows the move at once and saves it under the event's id", () async {
      final calendar = held();
      await calendar.refresh();
      final start = DateTime(2026, 9, 30, 9);
      final end = DateTime(2026, 9, 30, 9, 45);

      final moving = calendar.reschedule(shown(calendar, 14), start, end);
      expect(shown(calendar, 14).start, start);
      expect(shown(calendar, 14).end, end);

      await pumpEventQueue();
      final (draft, id) = server.saved.single;
      expect(id, 14);
      expect(draft.start, start);
      expect(draft.end, end);
      expect(draft.title, 'Event 14');
      expect(draft.reminderMinutes, 30);

      gates.single.complete();
      await moving;
      expect(shown(calendar, 14).start, start);
      expect(calendar.anchor, DateTime(2026, 9, 29));
    });

    test('moves a repeating event as a whole series', () async {
      final calendar = held();
      await calendar.refresh();
      // This week's practice, the fifth of the series.
      final practice = shown(calendar, 7);
      expect(practice.start, DateTime(2026, 10, 1, 17, 30));

      final moving = calendar.reschedule(
        practice,
        DateTime(2026, 10, 2, 18),
        DateTime(2026, 10, 2, 19),
      );
      expect(shown(calendar, 7).start, DateTime(2026, 10, 2, 18));
      await pumpEventQueue();
      gates.single.complete();
      await moving;

      // The series' first date moved a day and half an hour too, and it is
      // half an hour shorter.
      final (draft, id) = server.saved.single;
      expect(id, 7);
      expect(draft.start, DateTime(2026, 9, 4, 18));
      expect(draft.end, DateTime(2026, 9, 4, 19));
      expect(draft.repeat, CalendarRepeat.weekly);
      expect(shown(calendar, 7).end, DateTime(2026, 10, 2, 19));
    });

    test('a failed save rethrows and puts the event back', () async {
      final calendar = held();
      await calendar.refresh();
      final failure = const ApiException(500, 'save calendar event');

      final moving = calendar.reschedule(
        shown(calendar, 14),
        DateTime(2026, 9, 29, 10),
        DateTime(2026, 9, 29, 10, 45),
      );
      expect(shown(calendar, 14).start, DateTime(2026, 9, 29, 10));
      await pumpEventQueue();
      gates.single.completeError(failure);

      await expectLater(moving, throwsA(failure));
      expect(shown(calendar, 14).start, DateTime(2026, 9, 29, 16));
    });

    test('two quick moves of one event compound and save in order', () async {
      final calendar = held();
      await calendar.refresh();
      DateTime at(int minute) => DateTime(2026, 9, 29, 16, minute);

      final first = calendar.reschedule(shown(calendar, 14), at(15), at(60));
      // The second press sees the event where the first put it.
      expect(shown(calendar, 14).start, at(15));
      final second = calendar.reschedule(shown(calendar, 14), at(30), at(75));
      expect(shown(calendar, 14).start, at(30));

      // The second save waits for the first.
      await pumpEventQueue();
      expect([for (final (draft, _) in server.saved) draft.start], [at(15)]);
      gates[0].complete();
      await first;
      expect(shown(calendar, 14).start, at(30));

      await pumpEventQueue();
      expect(
        [for (final (draft, _) in server.saved) draft.start],
        [at(15), at(30)],
      );
      gates[1].complete();
      await second;
      expect(shown(calendar, 14).start, at(30));
      expect(shown(calendar, 14).end, at(75));
    });

    test('an event that is gone moves nothing', () async {
      final calendar = held();
      await calendar.refresh();
      final gone = CalendarEventItem(
        eventId: 404,
        title: 'Gone',
        start: _now,
        end: _now.add(const Duration(hours: 1)),
      );
      await calendar.reschedule(gone, _now, _now);
      expect(server.saved, isEmpty);
    });
  });

  group('person filter (#2544)', () {
    final mayaVet = _event(
      14,
      DateTime(2026, 9, 29, 16),
      const Duration(minutes: 45),
      reminder: 30,
      owner: 'maya',
      mine: true,
    );
    final samLunch = _event(
      15,
      DateTime(2026, 9, 29, 17),
      const Duration(hours: 1),
      reminder: 60,
      owner: 'sam',
    );
    final unowned = _event(
      16,
      DateTime(2026, 9, 30, 9),
      const Duration(hours: 1),
    );
    final events = [mayaVet, samLunch, unowned];

    Set<int> shown(CalendarController c) => {
      for (final o in c.occurrences) o.eventId,
    };
    Set<int> upcoming(CalendarController c) => {
      for (final day in c.upcoming)
        for (final o in day.events) o.eventId,
    };

    test('everyone is the default', () async {
      final c = _Server(events).controller();
      await c.show(CalendarView.week, DateTime(2026, 9, 29));
      await c.refresh();
      expect(shown(c), {14, 15, 16});
      expect(c.mineOnly, isFalse);
      expect(c.person, isNull);
    });

    test('My events narrows every view, upcoming and reminders', () async {
      final c = _Server(events).controller();
      await c.show(CalendarView.week, DateTime(2026, 9, 29), mineOnly: true);
      await c.refresh();
      expect(shown(c), {14});
      expect(upcoming(c), {14});
      expect(c.dueReminder?.eventId, 14);
    });

    test('one person hides everyone else, and their reminders', () async {
      final c = _Server(events).controller();
      await c.show(CalendarView.week, DateTime(2026, 9, 29), person: 'sam');
      await c.refresh();
      expect(shown(c), {15});
      expect(upcoming(c), {15});
      // Maya's reminder is due, but Sam's calendar is on show.
      expect(c.dueReminder, isNull);
    });

    test('changing only the filter loads nothing', () async {
      final server = _Server(events);
      final c = server.controller();
      await c.show(CalendarView.week, DateTime(2026, 9, 29));
      final loads = server.ranges.length;
      await c.show(CalendarView.week, DateTime(2026, 9, 29), mineOnly: true);
      expect(server.ranges.length, loads);
      expect(shown(c), {14});
    });

    test('My events wins over a person', () async {
      final c = _Server(events).controller();
      await c.show(
        CalendarView.week,
        DateTime(2026, 9, 29),
        mineOnly: true,
        person: 'sam',
      );
      expect(c.person, isNull);
      expect(shown(c), {14});
    });

    test('only an admin gets people to pick from', () async {
      final member = _Server(events).controller();
      await member.refresh();
      expect(member.people, isEmpty);

      final admin = _Server(events).controller(admin: true);
      await admin.refresh();
      expect(admin.people, ['maya', 'sam']);
    });
  });

  group('week start (#2539)', () {
    test('follows the locale', () {
      expect(firstWeekdayForLocale(const Locale('en', 'US')), DateTime.sunday);
      expect(firstWeekdayForLocale(const Locale('de', 'DE')), DateTime.monday);
      expect(firstWeekdayForLocale(const Locale('en', 'GB')), DateTime.monday);
      expect(
        firstWeekdayForLocale(const Locale('fa', 'IR')),
        DateTime.saturday,
      );
    });

    test('a script code or an unknown language falls back safely', () {
      expect(
        firstWeekdayForLocale(
          const Locale.fromSubtags(
            languageCode: 'sr',
            scriptCode: 'Latn',
            countryCode: 'RS',
          ),
        ),
        DateTime.monday,
      );
      expect(
        firstWeekdayForLocale(const Locale('xx')),
        CalendarDates.defaultFirstWeekday,
      );
    });

    test('the fetch and the grid share it', () async {
      final server = _Server([vet]);
      final c = server.controller();
      await c.show(
        CalendarView.month,
        DateTime(2026, 9, 29),
        firstWeekday: DateTime.monday,
      );
      expect(c.firstWeekday, DateTime.monday);
      expect(c.days.first, DateTime(2026, 8, 31));
      expect(server.ranges.last.$1, DateTime(2026, 8, 31));
      expect(server.ranges.last.$2, DateTime(2026, 10, 5));

      await c.show(
        CalendarView.week,
        DateTime(2026, 9, 29),
        firstWeekday: DateTime.saturday,
      );
      expect(c.days.first, DateTime(2026, 9, 26));
      expect(server.ranges.last.$1, DateTime(2026, 9, 26));
    });

    test('a new week start alone reloads the span', () async {
      final server = _Server([vet]);
      final c = server.controller();
      await c.show(CalendarView.week, DateTime(2026, 9, 29));
      final loads = server.ranges.length;
      await c.show(
        CalendarView.week,
        DateTime(2026, 9, 29),
        firstWeekday: DateTime.monday,
      );
      expect(server.ranges.length, loads + 1);
      expect(server.ranges.last.$1, DateTime(2026, 9, 28));
    });
  });
}
