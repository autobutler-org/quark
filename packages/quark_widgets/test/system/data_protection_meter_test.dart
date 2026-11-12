import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The three-step protection meter. The fill stops on the level it is given,
/// including when reduced motion skips the animation.
void main() {
  Color stepColor(WidgetTester tester, String step, {String? id}) {
    final key = id == null
        ? 'data_protection_meter_step_$step'
        : 'data_protection_meter_${id}_step_$step';
    final box = tester.widget<DecoratedBox>(find.byKey(ValueKey(key)));
    return (box.decoration as BoxDecoration).color!;
  }

  void expectFilled(
    WidgetTester tester,
    DataProtectionLevel level,
    QuarkTokens tokens,
  ) {
    final status = dataProtectionLevelColor(tokens, level);
    for (final step in DataProtectionLevel.values) {
      final filled = step.index <= level.index;
      expect(
        stepColor(tester, step.name),
        filled ? status : tokens.sidebar,
        reason: step.name,
      );
    }
  }

  for (final level in DataProtectionLevel.values) {
    testBothViewports('fills through ${level.label}', (tester, size) async {
      await pumpAt(tester, DataProtectionMeter(level: level), size: size);
      await tester.pumpAndSettle();

      expectFilled(tester, level, QuarkTokens.dark);
      expect(find.text(level.label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testBothViewports(
    'shows the reached step immediately when animations are disabled',
    (tester, size) async {
      await pumpAt(
        tester,
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: DataProtectionMeter(level: DataProtectionLevel.basic),
        ),
        size: size,
      );

      expectFilled(tester, DataProtectionLevel.basic, QuarkTokens.dark);
    },
  );

  testBothViewports(
    'shows the reached step immediately under platform reduce motion',
    (tester, size) async {
      reduceMotion(tester);
      await pumpAt(
        tester,
        const DataProtectionMeter(level: DataProtectionLevel.protected),
        size: size,
      );

      expectFilled(tester, DataProtectionLevel.protected, QuarkTokens.dark);
    },
  );

  testWidgets('jumps to the end when reduce motion turns on', (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpAt(
      tester,
      const DataProtectionMeter(level: DataProtectionLevel.basic),
    );

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();

    expectFilled(tester, DataProtectionLevel.basic, QuarkTokens.dark);
    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the fill comes from the tokens', (tester) async {
      await pumpAt(
        tester,
        const DataProtectionMeter(level: DataProtectionLevel.unprotected),
        brightness: brightness,
      );
      await tester.pumpAndSettle();

      expect(
        stepColor(tester, 'unprotected'),
        dataProtectionLevelColor(tokens, DataProtectionLevel.unprotected),
      );
      expect(stepColor(tester, 'protected'), tokens.sidebar);
    });
  }

  testWidgets('an id keeps a second meter\'s keys distinct', (tester) async {
    await pumpAt(
      tester,
      const Column(
        children: [
          DataProtectionMeter(level: DataProtectionLevel.basic),
          DataProtectionMeter(
            id: 'reduced',
            level: DataProtectionLevel.protected,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('data_protection_meter_step_basic')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('data_protection_meter_reduced_step_basic')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
