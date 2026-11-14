import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one form segmented control behind the repeat pickers (#4103): full
/// width, the picked segment tinted, no check mark, standard density.
void main() {
  Widget choice(String selected, ValueChanged<String> onChanged) =>
      QuarkSegmentedChoice<String>(
        segments: [
          for (final (id, label) in [
            ('none', 'Never'),
            ('daily', 'Daily'),
            ('weekly', 'Weekly'),
            ('monthly', 'Monthly'),
          ])
            ButtonSegment(
              value: id,
              label: Text(label, key: ValueKey('thing_$id'), maxLines: 1),
            ),
        ],
        selected: selected,
        onChanged: onChanged,
      );

  SegmentedButton<String> buttonOf(WidgetTester tester) => tester
      .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));

  testBothViewports('fits every segment and marks the selected one', (
    tester,
    size,
  ) async {
    await pumpAt(tester, choice('weekly', (_) {}), size: size);

    expect(tester.takeException(), isNull);
    for (final id in ['none', 'daily', 'weekly', 'monthly']) {
      expect(find.byKey(ValueKey('thing_$id')), findsOneWidget);
    }
    final button = buttonOf(tester);
    expect(button.selected, {'weekly'});
    expect(button.showSelectedIcon, isFalse);
    expect(button.style?.visualDensity, VisualDensity.standard);
  });

  testWidgets('reports the tapped segment', (tester) async {
    final picked = <String>[];
    await pumpAt(tester, choice('weekly', picked.add));

    await tester.tap(find.byKey(const ValueKey('thing_daily')));
    await tester.pump();

    expect(picked, ['daily']);
  });

  testWidgets('tints the selected segment with the primary color', (
    tester,
  ) async {
    await pumpAt(tester, choice('none', (_) {}));

    final tokens = QuarkTokens.dark;
    final style = buttonOf(tester).style!;
    expect(
      style.backgroundColor?.resolve({WidgetState.selected}),
      tokens.primary.withValues(alpha: 0.12),
    );
    expect(style.backgroundColor?.resolve({}), tokens.input);
  });
}
