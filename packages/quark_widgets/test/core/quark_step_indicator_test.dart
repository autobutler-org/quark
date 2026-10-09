/// [QuarkStepIndicator] names the step a multi-step flow is on and fills one
/// segment per step reached. First-boot setup showed no progress across its
/// three steps (#2026).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _steps = ['Create account', 'Recovery phrase', 'Theme'];

/// The fill color of segment [index].
Color? _segmentColor(WidgetTester tester, int index) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(ValueKey('step_indicator_segment_$index')),
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  for (final (index, label) in const [
    (0, 'Step 1 of 3 — Create account'),
    (1, 'Step 2 of 3 — Recovery phrase'),
    (2, 'Step 3 of 3 — Theme'),
  ]) {
    testBothViewports('names step ${index + 1} and fills up to it', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkStepIndicator(steps: _steps, currentIndex: index),
        size: size,
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(
        find.byKey(const ValueKey('step_indicator_label')),
      );
      expect(text.data, label);
      expect(find.byType(Text), findsOneWidget);

      final scheme = Theme.of(
        tester.element(find.byType(QuarkStepIndicator)),
      ).colorScheme;
      expect(scheme.primary, isNot(scheme.surfaceContainerHighest));
      for (var i = 0; i < _steps.length; i++) {
        expect(
          _segmentColor(tester, i),
          i <= index ? scheme.primary : scheme.surfaceContainerHighest,
          reason: 'segment $i at step $index',
        );
      }
      expect(
        find.byKey(ValueKey('step_indicator_segment_${_steps.length}')),
        findsNothing,
      );
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: the fill is the theme primary', (
      tester,
    ) async {
      await pumpAt(
        tester,
        QuarkStepIndicator(steps: _steps, currentIndex: 0),
        brightness: brightness,
      );

      final tokens = QuarkThemeColor.classic.tokensFor(brightness);
      expect(_segmentColor(tester, 0), tokens.primary);
    });
  }

  testBothViewports('survives a long step name', (tester, size) async {
    await pumpAt(
      tester,
      QuarkStepIndicator(
        steps: ['Create account', 'Recovery phrase ' * 20, 'Theme'],
        currentIndex: 1,
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
    expect(tester.getSize(find.byType(QuarkStepIndicator)).width, size.width);
  });

  testLargeText('keeps the label whole', (tester, size) async {
    await pumpAt(
      tester,
      QuarkStepIndicator(steps: _steps, currentIndex: 1),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  testWidgets('a screen reader hears the label and nothing else', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpAt(tester, QuarkStepIndicator(steps: _steps, currentIndex: 1));

    expect(
      find.bySemanticsLabel('Step 2 of 3 — Recovery phrase'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ExcludeSemantics),
        matching: find.byKey(const ValueKey('step_indicator_segment_0')),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final (name, steps, index) in [
    ('an empty list', <String>[], 0),
    ('a negative index', _steps, -1),
    ('an index past the last step', _steps, _steps.length),
  ]) {
    testWidgets('rejects $name', (tester) async {
      await pumpAt(
        tester,
        QuarkStepIndicator(steps: steps, currentIndex: index),
      );

      expect(tester.takeException(), isAssertionError);
    });
  }
}
