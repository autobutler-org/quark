import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/settings/quark_theme_color_picker/theme_color_swatch.dart';

import '../support/pump.dart';

const _custom = ValueKey('theme_color_custom');
const _slider = ValueKey('theme_color_hue_slider');
const _useDefault = ValueKey('theme_color_use_default');

ValueKey<String> _swatch(QuarkThemeColor preset) =>
    ValueKey('theme_color_swatch_${preset.name}');

/// The theme colors whose swatch is marked as chosen.
List<String> _selected(WidgetTester tester) => [
  for (final swatch in tester.widgetList<ThemeColorSwatch>(
    find.byType(ThemeColorSwatch),
  ))
    if (swatch.selected) swatch.label,
];

Widget _picker({
  QuarkThemeColor value = QuarkThemeColor.classic,
  ValueChanged<QuarkThemeColor>? onChanged,
  VoidCallback? onUseDefault,
  bool usingDefault = false,
}) => Center(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: QuarkThemeColorPicker(
      value: value,
      onChanged: onChanged ?? (_) {},
      onUseDefault: onUseDefault,
      usingDefault: usingDefault,
    ),
  ),
);

/// The theme color picker on Settings (#2740): presets, a custom hue, and
/// the choice to follow the Quark.
void main() {
  testBothViewports('offers every preset and marks the one in use', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _picker(value: QuarkThemeColor.violet), size: size);

    for (final preset in QuarkThemeColor.presets) {
      expect(find.byKey(_swatch(preset)), findsOneWidget);
      expect(find.byTooltip(preset.label), findsOneWidget);
    }
    expect(find.byKey(_custom), findsOneWidget);
    expect(find.byKey(_slider), findsOneWidget);
    expect(find.byKey(_useDefault), findsNothing);
    expect(_selected(tester), ['Violet']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('classic comes first, and each swatch hints at its theme', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _picker(), size: size, brightness: Brightness.light);

    final swatches = tester
        .widgetList<ThemeColorSwatch>(find.byType(ThemeColorSwatch))
        .toList();
    expect(swatches.map((s) => s.label), [
      'Classic',
      'Blue',
      'Indigo',
      'Violet',
      'Magenta',
      'Pink',
      'Lime',
      'Graphite',
      'Custom',
    ]);
    for (final (swatch, preset) in [
      for (final (index, preset) in QuarkThemeColor.presets.indexed)
        (swatches[index], preset),
    ]) {
      final tokens = preset.tokensFor(Brightness.light);
      expect(swatch.chrome, tokens.chrome, reason: preset.label);
      expect(swatch.accent, tokens.primary, reason: preset.label);
      // A disc of chrome with a dot of accent, not one flat color.
      expect(swatch.accent, isNot(swatch.chrome), reason: preset.label);
    }
    expect(_selected(tester), ['Classic']);
  });

  testBothViewports('reports the preset tapped', (tester, size) async {
    final picked = <QuarkThemeColor>[];
    await pumpAt(tester, _picker(onChanged: picked.add), size: size);

    for (final preset in QuarkThemeColor.presets) {
      await tester.tap(find.byKey(_swatch(preset)));
    }

    expect(picked, QuarkThemeColor.presets);
    expect(picked.map((a) => a.storageValue), [
      'classic',
      'blue',
      'indigo',
      'violet',
      'magenta',
      'pink',
      'lime',
      'graphite',
    ]);
  });

  testBothViewports(
    'a custom color marks the custom swatch and previews its theme',
    (tester, size) async {
      final value = QuarkThemeColor.fromSeed(const Color(0xFF22AA44));
      final picked = <QuarkThemeColor>[];
      await pumpAt(
        tester,
        _picker(value: value, onChanged: picked.add),
        size: size,
      );

      expect(_selected(tester), ['Custom']);
      final swatch = tester.widget<ThemeColorSwatch>(find.byKey(_custom));
      // Dark is pumpAt's default: the swatch previews the derived theme, not
      // the seed.
      final dark = value.tokensFor(Brightness.dark);
      expect(swatch.chrome, dark.chrome);
      expect(swatch.accent, dark.primary);
      expect(swatch.checkColor, dark.primaryForeground);
      expect(
        tester.widget<Slider>(find.byKey(_slider)).value,
        closeTo(HSLColor.fromColor(const Color(0xFF22AA44)).hue, 0.01),
      );

      await tester.tap(find.byKey(_custom));
      expect(picked, [value]);
    },
  );

  testWidgets('the custom swatch previews the mode on screen', (tester) async {
    final value = QuarkThemeColor.fromSeed(const Color(0xFF22AA44));
    await pumpAt(tester, _picker(value: value), brightness: Brightness.light);

    final swatch = tester.widget<ThemeColorSwatch>(find.byKey(_custom));
    final light = value.tokensFor(Brightness.light);
    expect(swatch.chrome, light.chrome);
    expect(swatch.accent, light.primary);
    expect(swatch.checkColor, light.primaryForeground);
    expect(light.chrome, isNot(value.tokensFor(Brightness.dark).chrome));
  });

  testBothViewports('dragging the slider previews, then reports once', (
    tester,
    size,
  ) async {
    final picked = <QuarkThemeColor>[];
    await pumpAt(tester, _picker(onChanged: picked.add), size: size);
    final before = tester.widget<ThemeColorSwatch>(find.byKey(_custom)).chrome;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_slider)),
    );
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();

    // Mid-drag: the swatch follows the thumb and nothing has been reported.
    final hue = tester.widget<Slider>(find.byKey(_slider)).value;
    final preview = QuarkThemeColor.fromSeed(
      QuarkThemeColorPicker.seedForHue(hue),
    );
    expect(picked, isEmpty);
    final swatch = tester.widget<ThemeColorSwatch>(find.byKey(_custom));
    expect(swatch.chrome, preview.tokensFor(Brightness.dark).chrome);
    expect(swatch.chrome, isNot(before));

    await gesture.up();
    await tester.pump();

    expect(picked, [preview]);
    expect(picked.single.isCustom, isTrue);
    expect(picked.single.storageValue, matches(RegExp(r'^#[0-9a-f]{6}$')));
    // The value is the caller's: until it changes, the thumb goes back.
    expect(
      tester.widget<Slider>(find.byKey(_slider)).value,
      closeTo(HSLColor.fromColor(QuarkTokens.dark.primary).hue, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('offers the Quark default only with a callback', (
    tester,
    size,
  ) async {
    var used = 0;
    await pumpAt(
      tester,
      _picker(value: QuarkThemeColor.pink, onUseDefault: () => used++),
      size: size,
    );

    expect(find.text("Use this Quark's default"), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.byKey(_useDefault)).selected,
      isFalse,
    );
    expect(_selected(tester), ['Pink']);

    await tester.tap(find.byKey(_useDefault));
    expect(used, 1);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('following the Quark marks that choice and no swatch', (
    tester,
    size,
  ) async {
    final picked = <QuarkThemeColor>[];
    await pumpAt(
      tester,
      _picker(
        value: QuarkThemeColor.pink,
        usingDefault: true,
        onChanged: picked.add,
        onUseDefault: () {},
      ),
      size: size,
    );

    expect(tester.widget<ChoiceChip>(find.byKey(_useDefault)).selected, isTrue);
    expect(_selected(tester), isEmpty);

    // Picking the color being followed still makes it the person's own.
    await tester.tap(find.byKey(_swatch(QuarkThemeColor.pink)));
    expect(picked, [QuarkThemeColor.pink]);
  });

  testWidgets('wraps on a phone instead of overflowing', (tester) async {
    await pumpAt(tester, _picker(onUseDefault: () {}), size: narrowViewport);

    final first = tester.getRect(
      find.byKey(_swatch(QuarkThemeColor.presets.first)),
    );
    final last = tester.getRect(find.byKey(_custom));
    expect(last.top, greaterThan(first.top));
    expect(last.right, lessThanOrEqualTo(narrowViewport.width));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(tester, _picker(onUseDefault: () {}), size: size);
    await expectTapTargetGuidelines(tester);
    expect(find.bySemanticsLabel('Classic'), findsOneWidget);
    expect(find.bySemanticsLabel('Custom'), findsOneWidget);
  });

  testLargeText('survives large text', (tester, size) async {
    await pumpAt(tester, _picker(onUseDefault: () {}), size: size);
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });
}
