import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The three-dot button that opens an item's menu under itself (#2267).
void main() {
  testBothViewports('drops the menu down from the button and runs the pick', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.topRight,
        child: QuarkMenuButton(
          key: const ValueKey('menu'),
          entries: [
            QuarkMenuEntry(
              key: const ValueKey('rename'),
              label: 'Rename',
              onSelected: () => events.add('rename'),
            ),
          ],
        ),
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('menu')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byKey(const ValueKey('menu')));
    final row = tester.getRect(find.byKey(const ValueKey('rename')));
    expect(row.top, greaterThanOrEqualTo(button.top));

    await tester.tap(find.byKey(const ValueKey('rename')));
    await tester.pumpAndSettle();

    expect(events, ['rename']);
  });

  testWidgets('is disabled with nothing to offer', (tester) async {
    await pumpAt(
      tester,
      const QuarkMenuButton(
        key: ValueKey('menu'),
        entries: [QuarkMenuEntry.divider()],
      ),
    );

    final button = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey('menu')),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('names itself', (tester) async {
    await pumpAt(
      tester,
      QuarkMenuButton(
        tooltip: 'Actions for ada',
        entries: [QuarkMenuEntry(label: 'Delete', onSelected: () {})],
      ),
    );

    expect(find.byTooltip('Actions for ada'), findsOneWidget);
  });
}
