import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The Everyone / My events / person row above the calendar (#2544).
void main() {
  bool active(WidgetTester tester, String key) =>
      tester.widget<QuarkBarChip>(find.byKey(ValueKey(key))).active;

  testBothViewports('marks whose events are shown', (tester, size) async {
    await pumpAt(
      tester,
      CalendarPersonFilter(mine: false, onEveryone: () {}, onMine: () {}),
      size: size,
    );
    expect(active(tester, 'calendar_filter_everyone'), isTrue);
    expect(active(tester, 'calendar_filter_mine'), isFalse);
    expect(find.byKey(const ValueKey('calendar_filter_people')), findsNothing);

    await pumpAt(
      tester,
      CalendarPersonFilter(mine: true, onEveryone: () {}, onMine: () {}),
      size: size,
    );
    expect(active(tester, 'calendar_filter_everyone'), isFalse);
    expect(active(tester, 'calendar_filter_mine'), isTrue);
    expect(find.text('My events'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('Everyone and My events call back', (tester, size) async {
    final tapped = <String>[];
    await pumpAt(
      tester,
      CalendarPersonFilter(
        mine: false,
        onEveryone: () => tapped.add('everyone'),
        onMine: () => tapped.add('mine'),
      ),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_filter_mine')));
    await tester.tap(find.byKey(const ValueKey('calendar_filter_everyone')));
    expect(tapped, ['mine', 'everyone']);
  });

  testBothViewports('the person chip picks one person', (tester, size) async {
    String? picked;
    await pumpAt(
      tester,
      CalendarPersonFilter(
        mine: false,
        people: const ['maya', 'sam'],
        onEveryone: () {},
        onMine: () {},
        onPerson: (name) => picked = name,
      ),
      size: size,
    );
    expect(find.text('Person'), findsOneWidget);
    final chip = find.byKey(const ValueKey('calendar_filter_people'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar_filter_person_sam')));
    await tester.pumpAndSettle();
    expect(picked, 'sam');
  });

  testBothViewports('a chosen person names the chip', (tester, size) async {
    await pumpAt(
      tester,
      CalendarPersonFilter(
        mine: false,
        person: 'maya',
        people: const ['maya', 'sam'],
        onEveryone: () {},
        onMine: () {},
        onPerson: (_) {},
      ),
      size: size,
    );
    expect(find.text('maya'), findsOneWidget);
    expect(active(tester, 'calendar_filter_people'), isTrue);
    expect(active(tester, 'calendar_filter_everyone'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
