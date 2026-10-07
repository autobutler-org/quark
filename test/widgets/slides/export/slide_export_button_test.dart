import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/export/slide_export_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// The slide editor's export button (#1172): it exports when tapped, shows a
/// spinner and refuses taps while an export runs, and is disabled with no
/// presentation to export.
void main() {
  const key = ValueKey('slide_editor_export_pptx');

  Future<void> pumpButton(
    WidgetTester tester, {
    required bool isExporting,
    required VoidCallback? onPressed,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        body: Center(
          child: SlideExportButton(
            isExporting: isExporting,
            onPressed: onPressed,
          ),
        ),
      ),
    ),
  );

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('exports when tapped, named by its tooltip ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      var exports = 0;
      await pumpButton(tester, isExporting: false, onPressed: () => exports++);

      expect(find.byTooltip(SlideExportButton.label), findsOneWidget);
      await tester.tap(find.byKey(key));
      expect(exports, 1);
      await tap.expectTapTargetGuidelines(tester);
    });

    testWidgets('refuses taps while an export runs ($name)', (tester) async {
      tap.setViewport(tester, size);
      var exports = 0;
      await pumpButton(tester, isExporting: true, onPressed: () => exports++);

      expect(find.byType(QuarkLoader), findsOneWidget);
      await tester.tap(find.byKey(key), warnIfMissed: false);
      expect(exports, 0);
    });

    testWidgets('is disabled with nothing to export ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pumpButton(tester, isExporting: false, onPressed: null);

      expect(
        tester.getSemantics(find.byKey(key)),
        isSemantics(isButton: true, isEnabled: false),
      );
    });
  }
}
