import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The "Allow account requests" switch on the Users page (#1908).
void main() {
  testBothViewports('shows the setting and reports the new one', (
    tester,
    size,
  ) async {
    final changes = <bool>[];
    await pumpAt(
      tester,
      AccessRequestsTile(enabled: true, onChanged: changes.add),
      size: size,
    );

    expect(find.text('Allow account requests'), findsOneWidget);
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('access_requests_toggle')),
    );
    expect(tile.value, isTrue);

    await tester.tap(find.byKey(const ValueKey('access_requests_toggle')));
    await tester.pump();

    expect(changes, [false]);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('holds still while a change is saving', (
    tester,
    size,
  ) async {
    final changes = <bool>[];
    await pumpAt(
      tester,
      AccessRequestsTile(enabled: false, isBusy: true, onChanged: changes.add),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('access_requests_toggle')));
    await tester.pump();

    expect(changes, isEmpty);
  });

  testWidgets('no callback disables the switch', (tester) async {
    await pumpAt(tester, const AccessRequestsTile(enabled: true));

    final tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('access_requests_toggle')),
    );
    expect(tile.onChanged, isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(
        tester,
        AccessRequestsTile(enabled: true, onChanged: (_) {}),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final subtitle = tester.widget<Text>(
        find.textContaining('People can ask'),
      );
      expect(subtitle.style?.color, tokens.mutedForeground);
    });
  }
}
