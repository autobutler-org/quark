import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/calendar/calendar_bar_bottom.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// #2603, #2605: the Calendar's second bar row is labeled 48dp targets in
/// every view, collapsed to its menu or spread out.
void main() {
  final anchor = DateTime(2026, 9, 29);

  for (final size in const [narrowViewport, wideViewport]) {
    for (final view in CalendarBarBottom.order) {
      testWidgets('${view.slug} is labeled 48dp targets at $size', (
        tester,
      ) async {
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CalendarBarBottom(
                    view: view,
                    anchor: anchor,
                    days: [
                      for (var i = 0; i < 7; i++)
                        CalendarDates.addDays(anchor, i),
                    ],
                    onPrevious: () {},
                    onNext: () {},
                    onToday: () {},
                    onViewSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await expectTapTargetGuidelines(tester);
      });
    }
  }
}
