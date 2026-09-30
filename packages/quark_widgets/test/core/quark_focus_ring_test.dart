import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Future<void> pumpRings(
    WidgetTester tester, {
    Size size = wideViewport,
    List<String>? events,
  }) => pumpAt(
    tester,
    Row(
      children: [
        for (final name in const ['first', 'second'])
          QuarkFocusRing(
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: ValueKey(name),
              onTap: () => events?.add(name),
              child: Container(
                width: 120,
                height: 60,
                color: Colors.teal,
                child: Text(name),
              ),
            ),
          ),
      ],
    ),
    size: size,
  );

  testBothViewports('shows no ring until the keyboard lands on it', (
    tester,
    size,
  ) async {
    await pumpRings(tester, size: size);

    expect(focusRingShown(tester, find.byKey(const ValueKey('first'))), false);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('rings only the child that holds focus', (
    tester,
    size,
  ) async {
    await pumpRings(tester, size: size);

    await tabTo(tester, find.byKey(const ValueKey('second')));

    expect(focusRingShown(tester, find.byKey(const ValueKey('second'))), true);
    expect(focusRingShown(tester, find.byKey(const ValueKey('first'))), false);
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find
                .ancestor(
                  of: find.byKey(const ValueKey('second')),
                  matching: find.byType(QuarkFocusRing),
                )
                .first,
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final border = (box.decoration as BoxDecoration).border! as Border;
    expect(border.top.width, 2);
    expect(border.top.color, QuarkTokens.dark.primary);
  });

  testWidgets('keeps focus on the child as the ring appears', (tester) async {
    final events = <String>[];
    await pumpRings(tester, events: events);

    await tabTo(tester, find.byKey(const ValueKey('first')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(events, ['first']);
  });
}
