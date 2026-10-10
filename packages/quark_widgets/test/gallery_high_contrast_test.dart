import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

// The gallery app lives in an example that depends on this package, so reaching
// it by path is what avoids a dependency cycle.
// ignore: avoid_relative_lib_imports
import '../examples/widget_gallery/lib/main.dart';
// ignore: avoid_relative_lib_imports
import '../examples/widget_gallery/lib/token_fields.dart';
// ignore: avoid_relative_lib_imports
import '../examples/widget_gallery/lib/widgets/gallery_theme_panel.dart';
import 'support/pump.dart';

/// The gallery's high-contrast option swaps in the high-contrast token sets and
/// exposes `focusRingWidth` for editing.
///
/// It runs at the wide viewport only: the gallery is a three-panel desktop tool
/// and overflows a phone in its token swatches, as `gallery_a11y_test.dart`
/// notes. Each widget's own test covers the narrow viewport.
void main() {
  QuarkTokens tokensOf(WidgetTester tester) =>
      QuarkTokens.of(tester.element(find.byType(Scaffold).first));

  Future<void> pumpGallery(WidgetTester tester) async {
    tester.view.physicalSize = wideViewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const WidgetGalleryApp());
  }

  testWidgets('app bar button switches to high contrast and back', (
    tester,
  ) async {
    await pumpGallery(tester);
    expect(tokensOf(tester), QuarkTokens.dark);

    final button = find.byKey(const ValueKey('gallery_high_contrast_button'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tokensOf(tester), QuarkTokens.highContrastDark);

    await tester.tap(find.byTooltip('Toggle light and dark'));
    await tester.pumpAndSettle();
    expect(tokensOf(tester), QuarkTokens.highContrastLight);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tokensOf(tester), QuarkTokens.light);
  });

  testWidgets('theme panel switch turns high contrast on', (tester) async {
    await pumpGallery(tester);

    await tester.tap(
      find.byKey(const ValueKey('gallery_high_contrast_switch')),
    );
    await tester.pumpAndSettle();
    expect(tokensOf(tester), QuarkTokens.highContrastDark);
  });

  /// #3071: picking a theme color used to turn high contrast off.
  testWidgets('high contrast follows the selected theme color', (tester) async {
    await pumpGallery(tester);
    await tester.tap(
      find.byKey(const ValueKey('gallery_high_contrast_switch')),
    );
    await tester.pumpAndSettle();

    final panel = tester.widget<GalleryThemePanel>(
      find.byType(GalleryThemePanel),
    );
    panel.onThemeColorChanged(QuarkThemeColor.violet);
    await tester.pumpAndSettle();

    final violet = QuarkThemeColor.violet.tokensFor(
      Brightness.dark,
      highContrast: true,
    );
    expect(tokensOf(tester), violet);
    expect(violet.primary, isNot(QuarkTokens.highContrastDark.primary));
  });

  test('focusRingWidth is an editable number token', () {
    final field = numberFields.singleWhere((f) => f.name == 'focusRingWidth');
    expect(field.read(QuarkTokens.highContrastDark), 3);
    expect(field.read(field.write(QuarkTokens.dark, 5)), 5);
  });
}
