import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The "Why two backup drives?" sheet: one copy versus three, and the
/// reminder to keep one drive somewhere else. It has no motion to reduce.
void main() {
  testBothViewports('shows one copy against three', (tester, size) async {
    await pumpAt(
      tester,
      const SingleChildScrollView(child: DataProtectionExplainerSheet()),
      size: size,
    );

    expect(
      find.byKey(const ValueKey('data_protection_explainer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('data_protection_explainer_one')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('data_protection_explainer_three')),
      findsOneWidget,
    );
    expect(find.text('One copy'), findsOneWidget);
    expect(find.text('Three copies'), findsOneWidget);
    expect(
      find.text('A fire, a theft, or a failed drive takes everything.'),
      findsOneWidget,
    );
    expect(find.textContaining('leaves the other two'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('data_protection_explainer_tip')),
      findsOneWidget,
    );
    expect(find.textContaining('somewhere else'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the tip sits on the sidebar token', (tester) async {
      await pumpAt(
        tester,
        const SingleChildScrollView(child: DataProtectionExplainerSheet()),
        brightness: brightness,
      );

      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('data_protection_explainer_tip')),
      );
      expect((box.decoration as BoxDecoration).color, tokens.sidebar);
    });
  }
}
