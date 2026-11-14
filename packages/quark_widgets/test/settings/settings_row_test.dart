import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _key = ValueKey('settings_row');

/// One row of a settings screen: a tap row or a switch row in a card, or a
/// flush switch row inside a section (#4104).
void main() {
  testBothViewports('tap row: shows its parts in a card and reports a tap', (
    tester,
    size,
  ) async {
    var taps = 0;
    await pumpAt(
      tester,
      SettingsRow(
        key: _key,
        leading: const Icon(QuarkIcons.storage),
        title: const Text('Storage devices'),
        subtitle: Text('View, mount and rename drives ' * 10),
        chevron: true,
        onTap: () => taps++,
      ),
      size: size,
    );

    expect(find.text('Storage devices'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.storage), findsOneWidget);
    expect(find.byIcon(QuarkIcons.chevron_right), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_key), matching: find.byType(Card)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_key));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no chevron unless asked', (tester) async {
    await pumpAt(tester, const SettingsRow(title: Text('Sign out')));
    expect(find.byIcon(QuarkIcons.chevron_right), findsNothing);
  });

  testWidgets('destructive: icon and title in the error color, subtitle not', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const SettingsRow(
        leading: Icon(QuarkIcons.restart),
        title: Text('Reset this Quark'),
        subtitle: Text('Erases every account'),
        destructive: true,
      ),
    );
    final error = Theme.of(
      tester.element(find.byType(SettingsRow)),
    ).colorScheme.error;

    expect(
      IconTheme.of(tester.element(find.byIcon(QuarkIcons.restart))).color,
      error,
    );
    expect(
      DefaultTextStyle.of(
        tester.element(find.text('Reset this Quark')),
      ).style.color,
      error,
    );
    expect(
      DefaultTextStyle.of(
        tester.element(find.text('Erases every account')),
      ).style.color,
      isNot(error),
    );
  });

  for (final (state, value) in [('on', true), ('off', false)]) {
    testBothViewports('switch row $state: reports the flipped value', (
      tester,
      size,
    ) async {
      final changes = <bool>[];
      await pumpAt(
        tester,
        SettingsRow.toggle(
          key: _key,
          title: const Text('Demo mode'),
          subtitle: const Text('Shows bundled sample photos'),
          value: value,
          onChanged: changes.add,
        ),
        size: size,
      );

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        value,
      );
      await tester.tap(find.byKey(_key));
      expect(changes, [!value]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switch row without a callback is disabled', (tester) async {
    await pumpAt(
      tester,
      const SettingsRow.toggle(title: Text('Demo mode'), value: true),
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
  });

  testWidgets('flush switch row: no card, no side padding', (tester) async {
    await pumpAt(
      tester,
      SettingsRow.toggle(
        title: const Text('Chat'),
        value: true,
        flush: true,
        onChanged: (_) {},
      ),
    );
    expect(find.byType(Card), findsNothing);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).contentPadding,
      EdgeInsets.zero,
    );
  });
}
