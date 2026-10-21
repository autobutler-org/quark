import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/src/vault/vault_autofill_setup.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('off: a filled button opens the setting', (
    tester,
    size,
  ) async {
    var taps = 0;
    await pumpAt(
      tester,
      Column(
        children: [
          VaultAutofillSetup(
            isOn: false,
            title: 'Fill passwords in other apps',
            message:
                'Choose Quark as your autofill service to fill your saved '
                'logins in your browser.',
            actionLabel: 'Turn on autofill',
            onOpenSettings: () => taps++,
          ),
        ],
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('vault_autofill_setup')), findsOneWidget);
    expect(find.text('Fill passwords in other apps'), findsOneWidget);
    final open = find.byKey(const ValueKey('vault_autofill_setup_open'));
    expect(tester.widget(open), isA<FilledButton>());
    await tester.tap(open);
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('on: says so, and still leads to the setting', (
    tester,
    size,
  ) async {
    var taps = 0;
    await pumpAt(
      tester,
      Column(
        children: [
          VaultAutofillSetup(
            isOn: true,
            title: 'Autofill is on',
            message: 'Quark fills your saved logins in your browser.',
            actionLabel: 'Change',
            onOpenSettings: () => taps++,
          ),
        ],
      ),
      size: size,
    );

    final open = find.byKey(const ValueKey('vault_autofill_setup_open'));
    expect(tester.widget(open), isA<TextButton>());
    expect(find.text('Change'), findsOneWidget);
    await tester.tap(open);
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
