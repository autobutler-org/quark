import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The tinted chip behind the beta mark (#2420), the drive health verdict and
/// the protection level: the word is always drawn, in the color it is given.
void main() {
  BoxDecoration decorationOf(WidgetTester tester, Key key) =>
      tester
              .widget<DecoratedBox>(
                find.descendant(
                  of: find.byKey(key),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .decoration
          as BoxDecoration;

  testBothViewports('beta reads Beta under its key', (tester, size) async {
    await pumpAt(
      tester,
      const Center(child: QuarkTintBadge.beta()),
      size: size,
    );

    expect(find.byKey(const ValueKey('beta_badge')), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final verdict in DriveHealthVerdict.values) {
    testBothViewports('reads ${verdict.label}', (tester, size) async {
      await pumpAt(
        tester,
        Center(
          child: QuarkTintBadge(
            key: const ValueKey('drive_health_badge'),
            label: verdict.label,
          ),
        ),
        size: size,
      );

      expect(find.text(verdict.label), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectNoClippedText(tester);
    });
  }

  testBothViewports('several badges keep their own keys', (tester, size) async {
    await pumpAt(
      tester,
      Wrap(
        children: [
          for (final level in DataProtectionLevel.values)
            QuarkTintBadge(
              key: ValueKey('data_protection_badge_${level.name}'),
              label: level.label,
            ),
        ],
      ),
      size: size,
    );

    for (final level in DataProtectionLevel.values) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('data_protection_badge_${level.name}')),
          matching: find.text(level.label),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a semantic label says what the word is about', (tester) async {
    await pumpAt(
      tester,
      const Center(
        child: QuarkTintBadge(label: 'Watch', semanticLabel: 'Watch health'),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('Watch health')), findsOneWidget);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: beta wears the accent from the tokens', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Center(child: QuarkTintBadge.beta()),
        brightness: brightness,
      );

      final decoration = decorationOf(tester, const ValueKey('beta_badge'));
      expect((decoration.border! as Border).top.color, tokens.primary);
      expect(
        tester.widget<Text>(find.text('Beta')).style?.color,
        tokens.primary,
      );
    });

    testWidgets('$label: the word and the outline share the given color', (
      tester,
    ) async {
      final color = driveHealthVerdictColor(tokens, DriveHealthVerdict.unknown);
      await pumpAt(
        tester,
        Center(
          child: QuarkTintBadge(
            key: const ValueKey('badge'),
            label: 'Unknown',
            color: color,
          ),
        ),
        brightness: brightness,
      );

      final decoration = decorationOf(tester, const ValueKey('badge'));
      expect((decoration.border! as Border).top.color, color);
      expect(tester.widget<Text>(find.text('Unknown')).style?.color, color);
      expect(color, isNot(tokens.success));
    });
  }
}
