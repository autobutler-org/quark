import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
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

    expect(find.byType(QuarkHelpDialog), findsOneWidget);
    expect(find.byIcon(QuarkIcons.lock_outline), findsOneWidget);
    for (final topic in QuarkEncryptionHelpDialog.topics) {
      expect(find.text(topic.body), findsOneWidget);
    }
    expect(
      QuarkEncryptionHelpDialog.topics.map((t) => t.body).join(' '),
      contains('verified'),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('quark_help_close')));
    await tester.tap(find.byKey(const ValueKey('quark_help_close')));
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });
}
