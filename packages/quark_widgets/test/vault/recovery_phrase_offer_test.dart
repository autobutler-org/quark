import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('offers, and reports adding and putting away', (
    tester,
    size,
  ) async {
    final taps = <String>[];
    await pumpAt(
      tester,
      Column(
        children: [
          RecoveryPhraseOffer(
            message:
                'Add your recovery phrase so a recovery keeps your vault and '
                'messages.',
            onAdd: () => taps.add('add'),
            onDismiss: () => taps.add('dismiss'),
          ),
        ],
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('recovery_phrase_offer')), findsOneWidget);
    expect(find.text('Add your recovery phrase'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recovery_phrase_offer_add')));
    await tester.tap(
      find.byKey(const ValueKey('recovery_phrase_offer_dismiss')),
    );
    expect(taps, ['add', 'dismiss']);
    expect(find.text('Add phrase'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
