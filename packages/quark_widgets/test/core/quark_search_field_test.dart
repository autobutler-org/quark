import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one search box behind the file-type, Photos and Files search strips
/// (#4102): one radius, one glyph size, and a close button the caller wires.
void main() {
  const fieldKey = ValueKey('thing_search');
  const dismissKey = ValueKey('thing_search_clear');

  InputDecoration decorationOf(WidgetTester tester) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byKey(fieldKey),
          matching: find.byType(TextField),
        ),
      )
      .decoration!;

  testBothViewports('lays out with the hint and both glyphs', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkSearchField(
        key: fieldKey,
        hintText: 'Search things…',
        onDismiss: () {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Search things…'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.search), findsOneWidget);
    expect(find.byIcon(QuarkIcons.close), findsOneWidget);
  });

  testWidgets('reports every edit', (tester) async {
    final typed = <String>[];
    await pumpAt(
      tester,
      QuarkSearchField(key: fieldKey, hintText: 'Search', onChanged: typed.add),
    );

    await tester.enterText(find.byKey(fieldKey), 'beach');

    expect(typed, ['beach']);
  });

  testWidgets('the close button reports once, under its key and tooltip', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkSearchField(
        key: fieldKey,
        hintText: 'Search',
        onDismiss: () => events.add('dismiss'),
        dismissTooltip: 'Close search',
        dismissKey: dismissKey,
      ),
    );

    await tester.tap(find.byKey(dismissKey));

    expect(events, ['dismiss']);
    expect(find.byTooltip('Close search'), findsOneWidget);
  });

  testWidgets('no close callback, no close button', (tester) async {
    await pumpAt(
      tester,
      const QuarkSearchField(
        key: fieldKey,
        hintText: 'Search',
        dismissKey: dismissKey,
      ),
    );

    expect(find.byKey(dismissKey), findsNothing);
    expect(find.byIcon(QuarkIcons.close), findsNothing);
  });

  testWidgets('both glyphs are the bar glyph size', (tester) async {
    await pumpAt(
      tester,
      QuarkSearchField(key: fieldKey, hintText: 'Search', onDismiss: () {}),
    );

    for (final glyph in [QuarkIcons.search, QuarkIcons.close]) {
      expect(tester.widget<Icon>(find.byIcon(glyph)).size, quarkMenuIconSize);
    }
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: fill and edge come from the tokens', (tester) async {
      await pumpAt(
        tester,
        const QuarkSearchField(key: fieldKey, hintText: 'Search'),
        brightness: brightness,
      );

      final decoration = decorationOf(tester);
      expect(decoration.fillColor, tokens.input);
      final border = decoration.enabledBorder! as OutlineInputBorder;
      expect(border.borderSide.color, tokens.border);
      expect(border.borderRadius, BorderRadius.circular(tokens.radiusMd));
    });
  }
}
