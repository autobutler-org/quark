import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one dropdown behind the settings, backup, vault and move pickers
/// (#4102): full width, grown to its text, and opening on the shared menu
/// panel (#4099).
void main() {
  const fieldKey = ValueKey('thing_picker');
  const items = [
    DropdownMenuItem(value: 'a', child: Text('Alpha')),
    DropdownMenuItem(value: 'b', child: Text('Beta')),
  ];

  DropdownButton<String> buttonOf(WidgetTester tester) =>
      tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(fieldKey),
          matching: find.byType(DropdownButton<String>),
        ),
      );

  testBothViewports('fills its row and shows the current choice', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDropdownField<String>(
        key: fieldKey,
        labelText: 'Thing',
        initialValue: 'a',
        items: items,
        onChanged: (_) {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Thing'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(tester.getSize(find.byKey(fieldKey)).width, size.width);
    expect(buttonOf(tester).isExpanded, isTrue);
  });

  testBothViewports('survives a long label', (tester, size) async {
    await pumpAt(
      tester,
      QuarkDropdownField<String>(
        key: fieldKey,
        initialValue: 'a',
        items: [
          DropdownMenuItem(
            value: 'a',
            child: Text(
              'Vacation ' * 30,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        onChanged: (_) {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('reports the pick once', (tester) async {
    final picked = <String?>[];
    await pumpAt(
      tester,
      QuarkDropdownField<String>(
        key: fieldKey,
        initialValue: 'a',
        items: items,
        onChanged: picked.add,
      ),
    );

    await tester.tap(find.byKey(fieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta').last);
    await tester.pumpAndSettle();

    expect(picked, ['b']);
  });

  testWidgets('no callback disables the field', (tester) async {
    await pumpAt(
      tester,
      const QuarkDropdownField<String>(
        key: fieldKey,
        initialValue: 'a',
        items: items,
        onChanged: null,
      ),
    );

    expect(buttonOf(tester).onChanged, isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the menu is the shared panel', (tester) async {
      await pumpAt(
        tester,
        QuarkDropdownField<String>(
          key: fieldKey,
          initialValue: 'a',
          items: items,
          onChanged: (_) {},
        ),
        brightness: brightness,
      );

      final button = buttonOf(tester);
      expect(button.dropdownColor, tokens.card);
      expect(button.borderRadius, BorderRadius.circular(tokens.radiusLg));
    });
  }
}
