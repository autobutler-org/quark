import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_status_bar.dart';

import '../../support/tap_targets.dart';

/// The page brightness toggle used to be a 24 pixel button in a 40 pixel bar
/// (#2605).
void main() {
  for (final (label, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('the brightness toggle is a 48 pixel target ($label)', (
      tester,
    ) async {
      setViewport(tester, size);
      var toggles = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: DocumentStatusBar(
                darkPage: false,
                onToggleDarkPage: () => toggles++,
                wordCount: 42,
                isReadOnly: false,
                dirty: false,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Switch to dark page'));
      await tester.pump();

      expect(toggles, 1);
      await expectTapTargetsMeetGuideline(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
