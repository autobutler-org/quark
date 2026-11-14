import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one pick-one-of-these menu (#4103): a chip naming the current choice,
/// a check on the selected row, the pick reported, and an optional tint.
void main() {
  Future<void> pumpMenu(
    WidgetTester tester, {
    Size size = wideViewport,
    String? selected = 'b',
    bool active = false,
    List<String?>? events,
  }) => pumpAt(
    tester,
    Center(
      child: QuarkChoiceMenu<String?>(
        keyPrefix: 'choice',
        icon: QuarkIcons.image_outlined,
        label: 'Pick: ${selected ?? 'none'}',
        tooltip: 'Pick one',
        options: const [
          (id: 'none', label: 'None', value: null),
          (id: 'a', label: 'Alpha', value: 'a'),
          (id: 'b', label: 'Bravo', value: 'b'),
        ],
        selected: selected,
        active: active,
        onChanged: (v) => events?.add(v),
      ),
    ),
    size: size,
  );

  testBothViewports('keeps its label and checks the selected row', (
    tester,
    size,
  ) async {
    await pumpMenu(tester, size: size);

    expect(find.text('Pick: b'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choice')));
    await tester.pumpAndSettle();

    for (final id in ['none', 'a', 'b']) {
      expect(find.byKey(ValueKey('choice_option_$id')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('choice_option_b')),
        matching: find.byIcon(QuarkIcons.check),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(QuarkIcons.check), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports the value of the row picked, null included', (
    tester,
  ) async {
    final events = <String?>[];
    await pumpMenu(tester, events: events);

    for (final id in ['a', 'none']) {
      await tester.tap(find.byKey(const ValueKey('choice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('choice_option_$id')));
      await tester.pumpAndSettle();
    }

    expect(events, ['a', null]);
  });

  for (final active in [false, true]) {
    testWidgets('passes active: $active to the chip', (tester) async {
      await pumpMenu(tester, active: active);

      final chip = tester.widget<QuarkBarChip>(
        find.byKey(const ValueKey('choice')),
      );
      expect(chip.active, active);
      expect(chip.keepLabel, isTrue);
    });
  }
}
