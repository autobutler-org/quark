import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _key = ValueKey('feature_flag_tile_chat');

FeatureFlagTile _tile({
  bool enabled = true,
  bool isBusy = false,
  ValueChanged<bool>? onChanged,
  String label = 'Chat',
}) => FeatureFlagTile(
  flagKey: 'chat',
  label: label,
  description: 'Hides the feature; stored data is kept.',
  enabled: enabled,
  isBusy: isBusy,
  onChanged: onChanged,
);

/// One beta feature's switch on the Settings Features tab (#2542).
void main() {
  testBothViewports('on: shows the flag and reports turning it off', (
    tester,
    size,
  ) async {
    final changes = <bool>[];
    await pumpAt(tester, _tile(onChanged: changes.add), size: size);

    expect(find.text('Chat'), findsOneWidget);
    expect(
      find.text('Hides the feature; stored data is kept.'),
      findsOneWidget,
    );
    expect(tester.widget<SwitchListTile>(find.byKey(_key)).value, isTrue);

    await tester.tap(find.byKey(_key));
    await tester.pump();

    expect(changes, [false]);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('off: reports turning it on', (tester, size) async {
    final changes = <bool>[];
    await pumpAt(
      tester,
      _tile(enabled: false, onChanged: changes.add),
      size: size,
    );

    expect(tester.widget<SwitchListTile>(find.byKey(_key)).value, isFalse);

    await tester.tap(find.byKey(_key));
    await tester.pump();

    expect(changes, [true]);
  });

  testBothViewports('busy: holds still while a change is saving', (
    tester,
    size,
  ) async {
    final changes = <bool>[];
    await pumpAt(
      tester,
      _tile(isBusy: true, onChanged: changes.add),
      size: size,
    );

    await tester.tap(find.byKey(_key));
    await tester.pump();

    expect(changes, isEmpty);
    expect(tester.widget<SwitchListTile>(find.byKey(_key)).onChanged, isNull);
  });

  testBothViewports('shows the beta badge next to the label', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _tile(), size: size);

    expect(
      find.descendant(
        of: find.byKey(_key),
        matching: find.byType(QuarkBetaBadge),
      ),
      findsOneWidget,
    );
  });

  testBothViewports('survives a long label', (tester, size) async {
    await pumpAt(tester, _tile(label: 'Chat ' * 40), size: size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no callback disables the switch', (tester) async {
    await pumpAt(tester, _tile());
    expect(tester.widget<SwitchListTile>(find.byKey(_key)).onChanged, isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(tester, _tile(onChanged: (_) {}), brightness: brightness);

      expect(tester.takeException(), isNull);
      final subtitle = tester.widget<Text>(find.textContaining('Hides'));
      expect(subtitle.style?.color, tokens.mutedForeground);
    });
  }
}
