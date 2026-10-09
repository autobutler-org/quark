import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets_example_widget_gallery/main.dart';
import 'package:quark_widgets_example_widget_gallery/widgets/gallery_theme_panel.dart';

QuarkTokens _tokens(WidgetTester tester) => tester
    .widget<MaterialApp>(find.byType(MaterialApp))
    .theme!
    .extension<QuarkTokens>()!;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const WidgetGalleryApp());
}

/// The gallery's high-contrast option swaps in the high-contrast tokens (#2938).
void main() {
  testWidgets('the switch selects the high-contrast dark then light tokens', (
    tester,
  ) async {
    await _pump(tester);
    expect(_tokens(tester), QuarkTokens.dark);

    await tester.tap(
      find.byKey(const ValueKey('gallery_high_contrast_switch')),
    );
    await tester.pump();
    expect(_tokens(tester), QuarkTokens.highContrastDark);

    await tester.tap(find.byTooltip('Toggle light and dark'));
    await tester.pump();
    expect(_tokens(tester), QuarkTokens.highContrastLight);

    await tester.tap(
      find.byKey(const ValueKey('gallery_high_contrast_button')),
    );
    await tester.pump();
    expect(_tokens(tester), QuarkTokens.light);
  });

  testWidgets('the focusRingWidth slider edits the token', (tester) async {
    await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('gallery_high_contrast_button')),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('focusRingWidth  3'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(GalleryThemePanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('focusRingWidth  3'), findsOneWidget);
  });
}
