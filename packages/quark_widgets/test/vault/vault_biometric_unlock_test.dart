import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Widget unlock({
    bool isBusy = false,
    String? error,
    VoidCallback? onUnlock,
    VoidCallback? onUsePassword,
  }) => VaultBiometricUnlock(
    title: 'Your vault is locked',
    message: 'Open it with Face ID, or with the password you sign in with.',
    unlockLabel: 'Unlock with Face ID',
    isBusy: isBusy,
    error: error,
    onUnlock: onUnlock ?? () {},
    onUsePassword: onUsePassword ?? () {},
  );

  testBothViewports('names the sensor and reports both choices', (
    tester,
    size,
  ) async {
    var unlocks = 0;
    var passwords = 0;
    await pumpAt(
      tester,
      unlock(onUnlock: () => unlocks++, onUsePassword: () => passwords++),
      size: size,
    );

    expect(find.text('Your vault is locked'), findsOneWidget);
    expect(find.text('Unlock with Face ID'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vault_biometric_unlock')));
    await tester.tap(
      find.byKey(const ValueKey('vault_biometric_unlock_password')),
    );
    expect(unlocks, 1);
    expect(passwords, 1);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('shows the caller\'s error, and holds still while busy', (
    tester,
    size,
  ) async {
    var taps = 0;
    await pumpAt(
      tester,
      unlock(
        isBusy: true,
        error: 'Too many tries. Unlock with your password for now.',
        onUnlock: () => taps++,
        onUsePassword: () => taps++,
      ),
      size: size,
    );

    expect(
      find.text('Too many tries. Unlock with your password for now.'),
      findsOneWidget,
    );
    expect(find.byType(QuarkLoader), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vault_biometric_unlock')));
    await tester.tap(
      find.byKey(const ValueKey('vault_biometric_unlock_password')),
    );
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });
}
