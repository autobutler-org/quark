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

  // #2482: the state is written out, not left to the switch's color.
  testBothViewports('says On while requests are on', (tester, size) async {
    await pumpAt(
      tester,
      AccessRequestsTile(enabled: true, onChanged: (_) {}),
      size: size,
    );

    expect(find.textContaining('On · ', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('People can ask', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Off · ', findRichText: true), findsNothing);
  });

  testBothViewports('says Off while requests are off', (tester, size) async {
    await pumpAt(
      tester,
      AccessRequestsTile(enabled: false, onChanged: (_) {}),
      size: size,
    );

    expect(find.textContaining('Off · ', findRichText: true), findsOneWidget);
    expect(
      find.textContaining("doesn't offer", findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('On · ', findRichText: true), findsNothing);
  });

  testWidgets('a screen reader hears the state with the label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAt(tester, AccessRequestsTile(enabled: false, onChanged: (_) {}));

    final label = tester
        .getSemantics(find.byKey(const ValueKey('access_requests_toggle')))
        .label;
    expect(label, contains('Allow account requests'));
    expect(label, contains('Off · '));
    handle.dispose();
  });

  testWidgets('says Saving while a change is saving', (tester) async {
    await pumpAt(
      tester,
      AccessRequestsTile(enabled: true, isBusy: true, onChanged: (_) {}),
    );

    expect(find.textContaining('Saving', findRichText: true), findsOneWidget);
  });

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets('lays out at 200% text ($size)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAt(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: AccessRequestsTile(enabled: false, onChanged: (_) {}),
        ),
        size: size,
      );

      expect(tester.takeException(), isNull);
      await expectTapTargetGuidelines(tester);
    });
  }

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
