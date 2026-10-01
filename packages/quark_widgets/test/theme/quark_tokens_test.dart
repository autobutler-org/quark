import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  group('QuarkTokens', () {
    test('copyWith replaces only what it is given', () {
      const base = QuarkTokens.dark;
      final edited = base.copyWith(
        primary: const Color(0xFF00FF00),
        radiusLg: 20,
      );

      expect(edited.primary, const Color(0xFF00FF00));
      expect(edited.radiusLg, 20);
      expect(edited.background, base.background);
      expect(edited.spacingMd, base.spacingMd);
    });

    test('copyWith with no arguments round-trips to an equal value', () {
      expect(QuarkTokens.dark.copyWith(), QuarkTokens.dark);
      expect(QuarkTokens.light.copyWith(), QuarkTokens.light);
      expect(QuarkTokens.dark.copyWith().hashCode, QuarkTokens.dark.hashCode);
    });

    test('dark and light are different token sets', () {
      expect(QuarkTokens.dark, isNot(QuarkTokens.light));
      expect(QuarkTokens.dark.background, isNot(QuarkTokens.light.background));
      // The accent is deliberately shared between the two.
      expect(QuarkTokens.dark.primary, QuarkTokens.light.primary);
    });

    test('lerp moves every value and ends on the target', () {
      final half = QuarkTokens.dark.lerp(QuarkTokens.light, 0.5);
      expect(half.background, isNot(QuarkTokens.dark.background));

      expect(QuarkTokens.dark.lerp(QuarkTokens.light, 1), QuarkTokens.light);
      expect(QuarkTokens.dark.lerp(null, 0.5), QuarkTokens.dark);
    });

    testWidgets('of() reads the tokens off the theme', (tester) async {
      final edited = QuarkTokens.light.copyWith(
        success: const Color(0xFF123456),
      );
      late QuarkTokens seen;

      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(edited, Brightness.light),
          home: Builder(
            builder: (context) {
              seen = QuarkTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(seen, edited);
      expect(seen.success, const Color(0xFF123456));
    });

    testWidgets('of() falls back to dark without the extension', (
      tester,
    ) async {
      late QuarkTokens seen;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Builder(
            builder: (context) {
              seen = QuarkTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(seen, QuarkTokens.dark);
    });

    test('both sets offer the same event colors, primary first', () {
      for (final tokens in [QuarkTokens.dark, QuarkTokens.light]) {
        expect(tokens.eventColors, hasLength(6));
        expect(tokens.eventColors.first, tokens.primary);
      }
    });

    test('event colors take part in equality and lerp', () {
      final recolored = QuarkTokens.dark.copyWith(
        eventColors: [...QuarkTokens.dark.eventColors]
          ..[1] = const Color(0xFF123456),
      );
      expect(recolored, isNot(QuarkTokens.dark));
      expect(
        QuarkTokens.dark.lerp(QuarkTokens.light, 1).eventColors,
        QuarkTokens.light.eventColors,
      );
    });

    test('QuarkColors still mirrors the dark tokens', () {
      expect(QuarkColors.background, QuarkTokens.dark.background);
      expect(QuarkColors.primary, QuarkTokens.dark.primary);
      expect(QuarkColors.radiusLg, QuarkTokens.dark.radiusLg);
    });
  });
}
