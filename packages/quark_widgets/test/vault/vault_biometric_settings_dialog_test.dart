import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const explanation =
      "Open your vault on this device with Face ID instead of your password. "
      'Anyone who can pass Face ID on this device can open your vault.';

  Widget dialog({
    bool value = false,
    bool isBusy = false,
    String? error,
    ValueChanged<bool>? onChanged,
    VoidCallback? onClose,
  }) => VaultBiometricSettingsDialog(
    title: 'Unlock with Face ID',
    explanation: explanation,
    value: value,
    isBusy: isBusy,
    error: error,
    onChanged: onChanged ?? (_) {},
    onClose: onClose ?? () {},
  );

  testBothViewports('explains before the switch, and reports what was asked', (
    tester,
    size,
  ) async {
    final asked = <bool>[];
    var closes = 0;
    await pumpAt(
      tester,
      dialog(onChanged: asked.add, onClose: () => closes++),
      size: size,
    );

    expect(find.text(explanation), findsOneWidget);
    expect(find.text('Unlock with Face ID'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('vault_biometric_switch')));
    await tester.tap(
      find.byKey(const ValueKey('vault_biometric_settings_close')),
    );
    expect(asked, [true]);
    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('turning off reports false', (tester, size) async {
    final asked = <bool>[];
    await pumpAt(tester, dialog(value: true, onChanged: asked.add), size: size);

    await tester.tap(find.byKey(const ValueKey('vault_biometric_switch')));
    expect(asked, [false]);
  });

  testBothViewports('holds the switch still while busy and shows the error', (
    tester,
    size,
  ) async {
    final asked = <bool>[];
    await pumpAt(
      tester,
      dialog(
        isBusy: true,
        error:
            "This device can't keep your vault behind a face or fingerprint.",
        onChanged: asked.add,
      ),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(
      find.text(
        "This device can't keep your vault behind a face or fingerprint.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('vault_biometric_switch')));
    expect(asked, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
