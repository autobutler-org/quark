import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Which occurrences of a repeating event a move changes (#3215).
void main() {
  testBothViewports('names the event and answers through its keys', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      CalendarMoveSeriesDialog(
        title: 'Soccer practice',
        onThisEvent: () => events.add('one'),
        onThisAndFollowing: () => events.add('following'),
        onAllEvents: () => events.add('all'),
        onCancel: () => events.add('cancel'),
      ),
      size: size,
    );
    expect(find.text('Move Soccer practice?'), findsOneWidget);
    expect(
      find.text('This event repeats. Choose which ones move.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('calendar_move_cancel')));
    await tester.tap(find.byKey(const ValueKey('calendar_move_this')));
    await tester.tap(find.byKey(const ValueKey('calendar_move_following')));
    await tester.tap(find.byKey(const ValueKey('calendar_move_all')));
    await tester.pump();
    expect(events, ['cancel', 'one', 'following', 'all']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('asks plainly about an untitled event, at large text', (
    tester,
    size,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpAt(
      tester,
      CalendarMoveSeriesDialog(
        title: '',
        onThisEvent: () {},
        onThisAndFollowing: () {},
        onAllEvents: () {},
        onCancel: () {},
      ),
      size: size,
    );
    expect(find.text('Move this repeating event?'), findsOneWidget);
    expect(find.text('This and following'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
