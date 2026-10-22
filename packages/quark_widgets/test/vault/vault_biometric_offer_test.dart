import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('offers, and reports turning on and putting away', (
    tester,
    size,
  ) async {
    final taps = <String>[];
    await pumpAt(
      tester,
      Column(
        children: [
          VaultBiometricOffer(
            title: 'Unlock with Face ID?',
            message:
                'Open your vault on this device without typing your password.',
            onEnable: () => taps.add('enable'),
            onDismiss: () => taps.add('dismiss'),
          ),
        ],
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('vault_biometric_offer')), findsOneWidget);
    expect(find.text('Unlock with Face ID?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('vault_biometric_offer_enable')),
    );
    await tester.tap(
      find.byKey(const ValueKey('vault_biometric_offer_dismiss')),
    );
    expect(taps, ['enable', 'dismiss']);
    expect(find.text('Turn on'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
