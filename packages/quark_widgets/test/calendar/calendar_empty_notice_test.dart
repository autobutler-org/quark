import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The calendar's soft empty card (#2538): its copy, its button, and how it
/// holds up on a phone with large text.
Widget _notice({VoidCallback? onAdd, String? subtext}) => Center(
  child: CalendarEmptyNotice(
    headline: 'Nothing planned this month',
    subtext: subtext,
    buttonKey: const ValueKey('calendar_month_add'),
    onAdd: onAdd,
  ),
);

void main() {
  testBothViewports('shows its copy and calls back from its button', (
    tester,
    size,
  ) async {
    var added = 0;
    await pumpAt(
      tester,
      _notice(onAdd: () => added++, subtext: 'Nothing scheduled'),
      size: size,
    );
    expect(find.text('Nothing planned this month'), findsOneWidget);
    expect(find.text('Nothing scheduled'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar_month_add')));
    expect(added, 1);
  });

  testWidgets('without a callback it has no button', (tester) async {
    await pumpAt(tester, _notice());
    expect(find.text('Nothing planned this month'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar_month_add')), findsNothing);
  });

  testBothViewports('wraps rather than overflows at twice the text size', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: _notice(onAdd: () {}, subtext: 'Nothing scheduled'),
        ),
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('its button is a labeled, full-size target', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _notice(onAdd: () {}), size: size);
    await expectTapTargetGuidelines(tester);
  });
}
