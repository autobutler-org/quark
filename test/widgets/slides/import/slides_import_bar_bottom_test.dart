import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/import/slides_import_bar_bottom.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// The Slides page's Import PowerPoint row (#1171).
void main() {
  late List<String> calls;

  setUp(() => calls = []);

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        appBar: QuarkAppBar(
          label: 'Slides',
          icon: QuarkIcons.slideshow_outlined,
          bottom: SlidesImportBarBottom(
            onImportFromQuark: () => calls.add('quark'),
            onImportFromDevice: () => calls.add('device'),
          ),
        ),
      ),
    ),
  );

  for (final (name, size, opener) in [
    ('narrow', tap.narrowViewport, 'app_bar_bottom_menu'),
    ('wide', tap.wideViewport, 'slides_import'),
  ]) {
    testWidgets('offers both sources behind one labeled control ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pump(tester);
      expect(find.text('Presentations'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey(opener)));
      await tester.pumpAndSettle();
      await tap.expectTapTargetGuidelines(tester);
      await tester.tap(find.byKey(const ValueKey('slides_import_from_quark')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(opener)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import_from_device')));
      await tester.pumpAndSettle();
      expect(calls, ['quark', 'device']);
      expect(tester.takeException(), isNull);
    });
  }
}
