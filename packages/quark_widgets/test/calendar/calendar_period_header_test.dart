import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The previous / title / next lead of the calendar's second bar row.
void main() {
  testBothViewports('shows the title and moves both ways', (
    tester,
    size,
  ) async {
    var previous = 0;
    var next = 0;
    await pumpAt(
      tester,
      CalendarPeriodHeader(
        title: 'September 2026',
        previousTooltip: 'Previous month',
        nextTooltip: 'Next month',
        onPrevious: () => previous++,
        onNext: () => next++,
      ),
      size: size,
    );
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.byTooltip('Previous month'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar_prev')));
    await tester.tap(find.byKey(const ValueKey('calendar_next')));
    await tester.tap(find.byKey(const ValueKey('calendar_next')));
    expect(previous, 1);
    expect(next, 2);
  });

  testWidgets('clips a long title in a narrow row', (tester) async {
    await pumpAt(
      tester,
      SizedBox(
        width: 160,
        child: CalendarPeriodHeader(
          title: 'Wednesday, September 30, 2026',
          onPrevious: () {},
          onNext: () {},
        ),
      ),
      size: narrowViewport,
    );
    expect(tester.takeException(), isNull);
  });
}
