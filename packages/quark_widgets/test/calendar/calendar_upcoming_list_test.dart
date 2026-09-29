import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The next seven days, grouped by date, with due reminders.
final _today = DateTime(2026, 9, 29);
final _now = DateTime(2026, 9, 29, 15, 40);

final _vet = CalendarEventItem(
  eventId: 14,
  title: 'Vet',
  start: DateTime(2026, 9, 29, 16),
  end: DateTime(2026, 9, 29, 16, 45),
  reminderMinutes: 30,
);
final _teacher = CalendarEventItem(
  eventId: 15,
  title: 'Parent–teacher night',
  start: DateTime(2026, 9, 29, 19),
  end: DateTime(2026, 9, 29, 20, 30),
  location: 'Lincoln Elementary',
  reminderMinutes: 60,
);
final _water = CalendarEventItem(
  eventId: 5,
  title: 'Pay water bill',
  start: DateTime(2026, 9, 30),
  end: DateTime(2026, 10, 1),
  allDay: true,
);
final _soccer = CalendarEventItem(
  eventId: 7,
  title: 'Soccer practice',
  start: DateTime(2026, 10, 1, 17, 30),
  end: DateTime(2026, 10, 1, 19),
  repeat: CalendarRepeat.weekly,
);

final _days = [
  CalendarDayEvents(day: _today, events: [_vet, _teacher]),
  CalendarDayEvents(day: DateTime(2026, 9, 30), events: [_water]),
  CalendarDayEvents(day: DateTime(2026, 10, 1), events: [_soccer]),
  CalendarDayEvents(day: DateTime(2026, 10, 2), events: const []),
];

Widget _list({
  List<CalendarDayEvents>? days,
  bool isLoading = false,
  String? error,
  ValueChanged<CalendarEventItem>? onEventTap,
  VoidCallback? onAddEvent,
}) => CalendarUpcomingList(
  days: days ?? _days,
  today: _today,
  now: _now,
  isLoading: isLoading,
  error: error,
  onEventTap: onEventTap,
  onAddEvent: onAddEvent,
);

void main() {
  testBothViewports('groups the events under today, tomorrow and weekdays', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _list(), size: size);
    expect(find.textContaining('Today'), findsOneWidget);
    expect(find.textContaining('Tomorrow'), findsOneWidget);
    expect(find.textContaining('Thursday'), findsOneWidget);
    expect(find.textContaining('Friday'), findsNothing);
    expect(find.text('All day'), findsOneWidget);
    expect(find.textContaining('Weekly'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a due reminder says how soon the event starts', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _list(), size: size);
    expect(find.text('Starts in 20 min'), findsOneWidget);
  });

  test('a reminder is due from its time until its event is past', () {
    expect(
      CalendarReminders.isDue(_vet, DateTime(2026, 9, 29, 15, 29)),
      isFalse,
    );
    expect(
      CalendarReminders.isDue(_vet, DateTime(2026, 9, 29, 15, 30)),
      isTrue,
    );
    expect(CalendarReminders.isDue(_vet, DateTime(2026, 9, 29, 16)), isFalse);
    expect(CalendarReminders.isDue(_water, _now), isFalse);
    final onTheDay = CalendarEventItem(
      eventId: 9,
      title: 'Garden waste',
      start: _today,
      end: DateTime(2026, 9, 30),
      allDay: true,
      reminderMinutes: -540,
    );
    expect(
      CalendarReminders.isDue(onTheDay, DateTime(2026, 9, 29, 8, 59)),
      isFalse,
    );
    expect(CalendarReminders.isDue(onTheDay, DateTime(2026, 9, 29, 9)), isTrue);
    expect(CalendarReminders.isDue(onTheDay, DateTime(2026, 9, 30)), isFalse);
    expect(CalendarReminders.dueLabel(onTheDay, _now), 'Today');
  });

  testBothViewports('taps through to the event', (tester, size) async {
    CalendarEventItem? tapped;
    await pumpAt(tester, _list(onEventTap: (e) => tapped = e), size: size);
    await tester.tap(
      find.byKey(const ValueKey('calendar_upcoming_7_2026-10-01')),
    );
    expect(tapped, _soccer);
  });

  testBothViewports('shows a loader while nothing has loaded', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _list(days: const [], isLoading: true), size: size);
    expect(find.byType(QuarkLoader), findsOneWidget);
  });

  testBothViewports('keeps the list under a refresh error', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _list(error: "Couldn't load your calendar."),
      size: size,
    );
    expect(find.text("Couldn't load your calendar."), findsOneWidget);
    expect(find.text('Vet'), findsOneWidget);
  });

  testBothViewports('an empty week offers to add an event', (
    tester,
    size,
  ) async {
    var adds = 0;
    await pumpAt(
      tester,
      _list(
        days: [CalendarDayEvents(day: _today, events: const [])],
        onAddEvent: () => adds++,
      ),
      size: size,
    );
    expect(find.text('Nothing in the next 7 days'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar_upcoming_add')));
    expect(adds, 1);
  });
}
