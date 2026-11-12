import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('fills to the fraction it is given', (tester, size) async {
    await pumpAt(tester, const QuarkStorageBar(usedFraction: 0.5), size: size);
    await tester.pumpAndSettle();

    final box = tester.widget<AnimatedFractionallySizedBox>(
      find.byType(AnimatedFractionallySizedBox),
    );
    expect(box.widthFactor, 0.5);
  });

  testBothViewports('clamps a fraction outside 0 to 1', (tester, size) async {
    await pumpAt(tester, const QuarkStorageBar(usedFraction: 1.8), size: size);

    final box = tester.widget<AnimatedFractionallySizedBox>(
      find.byType(AnimatedFractionallySizedBox),
    );
    expect(box.widthFactor, 1.0);
  });

  testWidgets('honors the height it is given', (tester) async {
    await pumpAt(
      tester,
      const QuarkStorageBar(usedFraction: 0.2, height: 20),
      size: narrowViewport,
    );

    expect(tester.getSize(find.byType(QuarkStorageBar)).height, 20);
  });

  test('escalates the fill color as the volume fills', () {
    const tokens = QuarkTokens.dark;

    expect(QuarkStorageBar.colorForFraction(0.0, tokens), tokens.primary);
    expect(QuarkStorageBar.colorForFraction(0.74, tokens), tokens.primary);
    expect(QuarkStorageBar.colorForFraction(0.75, tokens), tokens.warning);
    expect(QuarkStorageBar.colorForFraction(0.89, tokens), tokens.warning);
    expect(QuarkStorageBar.colorForFraction(0.9, tokens), tokens.error);
    expect(QuarkStorageBar.colorForFraction(1.0, tokens), tokens.error);
  });
}
