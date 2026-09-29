import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The chip that marks a feature as beta (#2420), drawn from the tokens.
void main() {
  testBothViewports('reads Beta by default', (tester, size) async {
    await pumpAt(tester, const Center(child: QuarkBetaBadge()), size: size);

    expect(find.byKey(const ValueKey('beta_badge')), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('reads the label it is given', (tester, size) async {
    await pumpAt(
      tester,
      const Center(child: QuarkBetaBadge(label: 'Preview')),
      size: size,
    );

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(
        tester,
        const Center(child: QuarkBetaBadge()),
        brightness: brightness,
      );

      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('beta_badge')),
      );
      final decoration = box.decoration as BoxDecoration;
      expect((decoration.border! as Border).top.color, tokens.primary);
      expect(
        tester.widget<Text>(find.text('Beta')).style?.color,
        tokens.primary,
      );
    });
  }
}
