import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The explainer behind every encryption "(?)" (#2496): what encryption,
/// keys and verification mean, without undefined jargon, at both sizes.
void main() {
  testBothViewports('explains keys and verification, then closes', (
    tester,
    size,
  ) async {
    var closed = 0;
    await pumpAt(
      tester,
      QuarkEncryptionHelpDialog(onClose: () => closed++),
      size: size,
    );

    for (final paragraph in QuarkEncryptionHelpDialog.paragraphs) {
      expect(find.text(paragraph.$2), findsOneWidget);
    }
    expect(
      QuarkEncryptionHelpDialog.paragraphs.map((p) => p.$2).join(' '),
      contains('verified'),
    );
    await tester.tap(find.byKey(const ValueKey('encryption_help_close')));
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });
}
