import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/toolbar/slide_color_palette.dart';
import 'package:quark/widgets/slides/toolbar/slide_hex_field.dart';
import 'package:quark/widgets/slides/toolbar/slide_swatch_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_swatches.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// The slide color palette (#1167): token swatches, none, and custom hex.
void main() {
  late List<SlideColor?> picked;

  Future<void> pump(
    WidgetTester tester, {
    SlideColor? current,
    bool enabled = true,
    SlideTheme? theme,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        body: Center(
          child: SlideColorPalette(
            choice: SlideColorChoice(
              key: 'fill',
              label: 'Fill color',
              icon: QuarkIcons.format_fill,
              current: current,
              noneLabel: 'No fill',
              theme: theme,
              onChanged: enabled ? picked.add : null,
            ),
          ),
        ),
      ),
    ),
  );

  setUp(() => picked = []);

  test('the swatches start with black and white, then the tokens, once', () {
    final swatches = slideSwatches(QuarkTokens.light);
    expect(swatches.take(2).map((s) => s.name), ['Black', 'White']);
    expect(swatches.map((s) => s.color).toSet(), hasLength(swatches.length));
    expect(
      swatches.map((s) => s.color),
      contains(SlideColor(QuarkTokens.light.primary.toARGB32())),
    );
  });

  test('the hex field reads #RRGGBB and nothing else', () {
    expect(SlideHexField.parse('#12ab34'), const SlideColor(0xFF12AB34));
    expect(SlideHexField.parse('12AB34'), const SlideColor(0xFF12AB34));
    expect(SlideHexField.parse('#12ab3'), isNull);
    expect(SlideHexField.parse('red'), isNull);
    expect(SlideHexField.format(const SlideColor(0x8012AB34)), '#12AB34');
  });

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('picks a swatch, none, or a typed color ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pump(tester, current: SlideColor.white);

      expect(
        tester.getSemantics(find.byKey(const ValueKey('fill_1'))),
        isSemantics(label: 'White', isSelected: true, isButton: true),
      );
      await tester.tap(find.byKey(const ValueKey('fill_0')));
      await tester.tap(find.byKey(const ValueKey('fill_none')));
      await tester.enterText(find.byKey(const ValueKey('fill_hex')), 'zz');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Type a color as #RRGGBB'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('fill_hex')), '#00ff00');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(picked, [SlideColor.black, null, const SlideColor(0xFF00FF00)]);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  test('names the theme roles for people', () {
    expect(themeSwatches().map((s) => s.name), [
      'Background',
      'Text',
      'Background 2',
      'Text 2',
      for (var i = 1; i <= 6; i++) 'Accent $i',
    ]);
    expect(
      themeSwatches().map((s) => s.color),
      everyElement(predicate<SlideColor>((c) => c.isThemeColor)),
    );
  });

  testWidgets('offers the theme\'s colors first, writing the role (#1163)', (
    tester,
  ) async {
    await pump(
      tester,
      theme: SlideThemes.dark,
      current: const SlideColor.theme(ThemeColor.accent2),
    );
    final accent1 = find.byKey(const ValueKey('fill_theme_accent1'));
    // Drawn in the deck's theme, not the role's light fallback.
    final swatch = tester.widget<SlideSwatchButton>(accent1);
    expect(swatch.color, Color(SlideThemes.dark.colors[ThemeColor.accent1]));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('fill_theme_accent2'))),
      isSemantics(label: 'Accent 2', isSelected: true, isButton: true),
    );
    expect(
      tester.getTopLeft(accent1).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('fill_0'))).dy),
    );
    // The hex field reads the role's value in the theme.
    final hex = SlideHexField.format(
      SlideColor(SlideThemes.dark.colors[ThemeColor.accent2]),
    );
    expect(find.text(hex), findsOneWidget);

    await tester.tap(accent1);
    expect(picked, [const SlideColor.theme(ThemeColor.accent1)]);
  });

  testWidgets('a deck with no theme draws roles in the app\'s colors', (
    tester,
  ) async {
    await pump(tester);
    final swatch = tester.widget<SlideSwatchButton>(
      find.byKey(const ValueKey('fill_theme_accent1')),
    );
    expect(
      swatch.color,
      QuarkTheme.light(themeColor: QuarkThemeColor.classic).colorScheme.primary,
    );
  });

  testWidgets('does nothing while the color does not apply', (tester) async {
    await pump(tester, enabled: false);
    await tester.tap(find.byKey(const ValueKey('fill_2')));
    expect(picked, isEmpty);
  });
}
