import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/core/quark_loader/quark_loader_painter.dart';

import '../support/pump.dart';

QuarkLoaderPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(QuarkLoader),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as QuarkLoaderPainter;

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(
        of: find.byType(QuarkLoader),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

Future<void> _expectPulsing(WidgetTester tester) async {
  expect(_painter(tester).progress, isNull);
  final before = _opacity(tester);
  await tester.pump(const Duration(milliseconds: 800));
  expect(_painter(tester).progress, isNull);
  expect(_opacity(tester), isNot(before));
}

void main() {
  testBothViewports('spins and renders at the requested size', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const Center(child: QuarkLoader(size: 48)),
      size: size,
    );

    expect(tester.getSize(find.byType(QuarkLoader)), const Size.square(48));
    final before = _painter(tester).progress;
    expect(before, isNotNull);
    expect(_opacity(tester), 1.0);

    await tester.pump(const Duration(milliseconds: 250));
    expect(_painter(tester).progress, isNot(before));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('defaults to the CircularProgressIndicator footprint', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const Center(child: QuarkLoader()), size: size);

    expect(tester.getSize(find.byType(QuarkLoader)), const Size.square(36));
    final tokens = QuarkTokens.of(tester.element(find.byType(QuarkLoader)));
    expect(_painter(tester).ringColor, tokens.primary);
    expect(_painter(tester).trackColor, tokens.border);
  });

  testBothViewports('pulses instead of spinning when animations are disabled', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Center(child: QuarkLoader()),
      ),
      size: size,
    );

    await _expectPulsing(tester);
  });

  testBothViewports('pulses instead of spinning under platform reduce motion', (
    tester,
    size,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await pumpAt(tester, const Center(child: QuarkLoader()), size: size);

    await _expectPulsing(tester);
  });

  testWidgets('switches mode when accessibility features change', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpAt(tester, const Center(child: QuarkLoader()));
    expect(_painter(tester).progress, isNotNull);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    await _expectPulsing(tester);

    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    expect(_painter(tester).progress, isNotNull);
  });
}
