import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/recover_page.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #2034: the recovery form asked for a "Recovery phrase" with only a
/// `word-word-…` hint, which says nothing to someone who last saw the phrase
/// months ago. The field now says what the phrase is and when it was shown.
void main() {
  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('the phrase field says where the phrase came from at $size', (
      tester,
    ) async {
      setViewport(tester, size);

      await tester.pumpWidget(const MaterialApp(home: RecoverPage()));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Recovery phrase'),
          matching: find.textContaining('The words Quark showed once'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
