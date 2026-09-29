import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one-line event chip: its two shapes, its dense size, and its key.
final _timed = CalendarEventItem(
  eventId: 7,
  title: 'Plumber visit',
  start: DateTime(2026, 9, 29, 9),
  end: DateTime(2026, 9, 29, 10),
);
final _allDay = CalendarEventItem(
  eventId: 8,
  title: 'Rent due',
  start: DateTime(2026, 10, 1),
  end: DateTime(2026, 10, 2),
  allDay: true,
  colorIndex: 2,
);

Widget _chip(
  CalendarEventItem item, {
  bool dense = false,
  VoidCallback? onTap,
}) => SizedBox(
  width: 160,
  child: CalendarEventChip(item: item, dense: dense, onTap: onTap),
);

void main() {
  testBothViewports('a timed chip shows its start time', (tester, size) async {
    await pumpAt(tester, Center(child: _chip(_timed)), size: size);
    expect(find.text('9am'), findsOneWidget);
    expect(find.text('Plumber visit'), findsOneWidget);
  });

  testBothViewports('an all-day chip is a filled bar with no time', (
    tester,
    size,
  ) async {
    await pumpAt(tester, Center(child: _chip(_allDay)), size: size);
    expect(find.text('Rent due'), findsOneWidget);
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('Rent due'), matching: find.byType(Material))
          .first,
    );
    expect(
      material.color,
      QuarkTokens.dark.eventColors[2].withValues(alpha: 0.24),
    );
  });

  testBothViewports('a dense chip drops the time', (tester, size) async {
    await pumpAt(tester, Center(child: _chip(_timed, dense: true)), size: size);
    expect(find.text('9am'), findsNothing);
    expect(find.text('Plumber visit'), findsOneWidget);
  });

  testBothViewports('taps through its occurrence key', (tester, size) async {
    var taps = 0;
    await pumpAt(
      tester,
      Center(child: _chip(_timed, onTap: () => taps++)),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_event_7_2026-09-29')));
    expect(taps, 1);
  });

  test('an unknown color index falls back to the first color', () {
    expect(
      eventColor(QuarkTokens.dark, 99),
      QuarkTokens.dark.eventColors.first,
    );
    expect(eventColor(QuarkTokens.dark, 3), QuarkTokens.dark.eventColors[3]);
  });
}
