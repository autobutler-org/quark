import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The due-reminder bar above the calendar views.
final _now = DateTime(2026, 9, 29, 15, 40);

final _vet = CalendarEventItem(
  eventId: 14,
  title: 'Vet',
  start: DateTime(2026, 9, 29, 16),
  end: DateTime(2026, 9, 29, 16, 45),
  reminderMinutes: 30,
);

final _rent = CalendarEventItem(
  eventId: 1,
  title: 'Rent due',
  start: DateTime(2026, 9, 30),
  end: DateTime(2026, 10, 1),
  allDay: true,
  reminderMinutes: 900,
);

void main() {
  testBothViewports('says when a timed event starts', (tester, size) async {
    await pumpAt(
      tester,
      CalendarReminderBanner(item: _vet, now: _now),
      size: size,
    );
    expect(find.text('Vet starts at 4:00 PM · in 20 min'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testBothViewports('says which day an all-day event falls on', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      CalendarReminderBanner(item: _rent, now: _now),
      size: size,
    );
    expect(find.text('Rent due is tomorrow'), findsOneWidget);
  });

  testBothViewports('opens and dismisses', (tester, size) async {
    var opens = 0;
    var dismissals = 0;
    await pumpAt(
      tester,
      CalendarReminderBanner(
        item: _vet,
        now: _now,
        onOpen: () => opens++,
        onDismiss: () => dismissals++,
      ),
      size: size,
    );
    await tester.tap(
      find.byKey(const ValueKey('calendar_reminder_open_14_2026-09-29')),
    );
    await tester.tap(
      find.byKey(const ValueKey('calendar_reminder_dismiss_14_2026-09-29')),
    );
    expect((opens, dismissals), (1, 1));
  });
}
