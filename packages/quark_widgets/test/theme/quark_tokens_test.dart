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
      // The accent is one hue, a shade deeper on light: sky-500 falls to
      // 2.77:1 on white, below WCAG AA (#2600).
      expect(QuarkTokens.dark.primary, isNot(QuarkTokens.light.primary));
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

    test('QuarkColors still mirrors the dark tokens', () {
      expect(QuarkColors.background, QuarkTokens.dark.background);
      expect(QuarkColors.primary, QuarkTokens.dark.primary);
      expect(QuarkColors.radiusLg, QuarkTokens.dark.radiusLg);
    });
  });
}
