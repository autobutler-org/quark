import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The members an `@mention` could name (#2623): a row each, a tap picks
/// one, and the row the keyboard is on is marked.
void main() {
  const names = ['ada', 'ann', 'bob'];

  Color? tintOf(WidgetTester tester, String name) => tester
      .widget<Container>(
        find.descendant(
          of: find.byKey(ValueKey('mention_suggestion_$name')),
          matching: find.byType(Container),
        ),
      )
      .color;

  testBothViewports('lists each name and picks the one tapped', (
    tester,
    size,
  ) async {
    final picked = <String>[];
    await pumpAt(
      tester,
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: QuarkMentionSuggestions(names: names, onSelect: picked.add),
        ),
      ),
      size: size,
    );

    for (final name in names) {
      expect(find.text('@$name'), findsOneWidget);
    }
    await expectTapTargetGuidelines(tester);
    await tester.tap(find.byKey(const ValueKey('mention_suggestion_ann')));
    expect(picked, ['ann']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks only the highlighted row', (tester) async {
    await pumpAt(
      tester,
      QuarkMentionSuggestions(
        names: names,
        highlighted: 'ann',
        onSelect: (_) {},
      ),
    );

    expect(tintOf(tester, 'ann'), isNotNull);
    expect(tintOf(tester, 'ada'), isNull);
  });

  testBothViewports('takes no space with no names', (tester, size) async {
    await pumpAt(
      tester,
      Center(
        child: QuarkMentionSuggestions(names: const [], onSelect: (_) {}),
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('mention_suggestions')), findsNothing);
    expect(tester.getSize(find.byType(QuarkMentionSuggestions)), Size.zero);
  });

  testBothViewports('scrolls past its height and keeps a long name on a row', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: QuarkMentionSuggestions(
          names: [for (var i = 0; i < 20; i++) 'member-$i-${'x' * 80}'],
          onSelect: (_) {},
        ),
      ),
      size: size,
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('mention_suggestions'))).height,
      240,
    );
    expect(tester.takeException(), isNull);
  });

  testLargeText('survives large text', (tester, size) async {
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: QuarkMentionSuggestions(names: names, onSelect: (_) {}),
      ),
      size: size,
    );

    expectNoClippedText(tester);
    expect(tester.takeException(), isNull);
  });
}
