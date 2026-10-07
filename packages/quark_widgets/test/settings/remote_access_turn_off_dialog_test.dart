import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The confirmation before an admin turns remote access off for everyone
/// (#2857).
void main() {
  testBothViewports('says what turning off does, and asks', (
    tester,
    size,
  ) async {
    final taps = <String>[];
    await pumpAt(
      tester,
      RemoteAccessTurnOffDialog(
        onCancel: () => taps.add('cancel'),
        onConfirm: () => taps.add('confirm'),
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Turn off remote access for everyone?'), findsOneWidget);
    expect(
      find.textContaining('At home, everything keeps working'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('remote_access_turn_off_cancel')),
    );
    await tester.tap(
      find.byKey(const ValueKey('remote_access_turn_off_confirm')),
    );
    expect(taps, ['cancel', 'confirm']);
  });

  testLargeText('survives large text', (tester, size) async {
    await pumpAt(
      tester,
      RemoteAccessTurnOffDialog(onCancel: () {}, onConfirm: () {}),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });
}
