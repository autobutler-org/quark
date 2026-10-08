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
      // Each mode has its own shade of the classic blue (#2523).
      expect(QuarkTokens.dark.primary, isNot(QuarkTokens.light.primary));
    });

    test('lerp moves every value and ends on the target', () {
      final half = QuarkTokens.dark.lerp(QuarkTokens.light, 0.5);
      expect(half.background, isNot(QuarkTokens.dark.background));

      expect(QuarkTokens.dark.lerp(QuarkTokens.light, 1), QuarkTokens.light);
      expect(QuarkTokens.dark.lerp(null, 0.5), QuarkTokens.dark);
    });

    test('the chrome tokens take part in copyWith, equality and lerp', () {
      const base = QuarkTokens.light;
      for (final (edited, read) in <(QuarkTokens, Color Function(QuarkTokens))>[
        (base.copyWith(chrome: _marker), (t) => t.chrome),
        (base.copyWith(chromeBorder: _marker), (t) => t.chromeBorder),
        (base.copyWith(chromeForeground: _marker), (t) => t.chromeForeground),
        (
          base.copyWith(chromeSecondaryForeground: _marker),
          (t) => t.chromeSecondaryForeground,
        ),
        (
          base.copyWith(chromeMutedForeground: _marker),
          (t) => t.chromeMutedForeground,
        ),
        (base.copyWith(chromePrimary: _marker), (t) => t.chromePrimary),
      ]) {
        expect(read(edited), _marker);
        expect(edited, isNot(base));
        expect(edited.hashCode, isNot(base.hashCode));
        expect(read(base.lerp(edited, 1)), _marker);
        expect(read(base.lerp(edited, 0.5)), isNot(read(base)));
      }
    });

    test('onChrome swaps in the chrome text, hairline and accent', () {
      final tokens = QuarkThemeColor.violet.tokensFor(Brightness.light);
      final onChrome = tokens.onChrome;

      expect(onChrome.foreground, tokens.chromeForeground);
      expect(onChrome.cardForeground, tokens.chromeForeground);
      expect(onChrome.secondaryForeground, tokens.chromeSecondaryForeground);
      expect(onChrome.mutedForeground, tokens.chromeMutedForeground);
      expect(onChrome.border, tokens.chromeBorder);
      expect(onChrome.primary, tokens.chromePrimary);
      expect(onChrome, isNot(tokens));
      // Surfaces, the accent's foreground and the scale are left alone.
      expect(
        onChrome,
        tokens.copyWith(
          foreground: tokens.chromeForeground,
          cardForeground: tokens.chromeForeground,
          secondaryForeground: tokens.chromeSecondaryForeground,
          mutedForeground: tokens.chromeMutedForeground,
          border: tokens.chromeBorder,
          primary: tokens.chromePrimary,
        ),
      );
      expect(onChrome.onChrome, onChrome);
      // The shipped sets draw chrome the way they draw content.
      expect(QuarkTokens.light.onChrome, QuarkTokens.light);
      expect(QuarkTokens.dark.onChrome, QuarkTokens.dark);
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

    test('both sets offer the same event colors, the same blue first', () {
      for (final tokens in [QuarkTokens.dark, QuarkTokens.light]) {
        expect(tokens.eventColors, hasLength(6));
        // An event stores its index, and its color does not follow the
        // theme color (#2740).
        expect(tokens.eventColors.first, const Color(0xFF0EA5E9));
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

  /// #2601: the high-contrast sets aim for WCAG AAA.
  group('high-contrast tokens', () {
    for (final (name, tokens) in [
      ('dark', QuarkTokens.highContrastDark),
      ('light', QuarkTokens.highContrastLight),
    ]) {
      final surfaces = {
        'background': tokens.background,
        'card': tokens.card,
        'sidebar': tokens.sidebar,
        'input': tokens.input,
        'chrome': tokens.chrome,
      };

      test('$name: every text token is 7:1 on every surface', () {
        final texts = {
          'foreground': tokens.foreground,
          'cardForeground': tokens.cardForeground,
          'secondaryForeground': tokens.secondaryForeground,
          'mutedForeground': tokens.mutedForeground,
          'primary': tokens.primary,
          'error': tokens.error,
          'chromeForeground': tokens.chromeForeground,
          'chromeSecondaryForeground': tokens.chromeSecondaryForeground,
          'chromeMutedForeground': tokens.chromeMutedForeground,
          'chromePrimary': tokens.chromePrimary,
        };
        for (final text in texts.entries) {
          for (final surface in surfaces.entries) {
            expect(
              contrastRatio(text.value, surface.value),
              greaterThanOrEqualTo(7),
              reason: '${text.key} on ${surface.key}',
            );
          }
        }
      });

      test('$name: text on the accent and error fills is 7:1', () {
        expect(
          contrastRatio(tokens.primaryForeground, tokens.primary),
          greaterThanOrEqualTo(7),
        );
        expect(
          contrastRatio(tokens.primaryForeground, tokens.chromePrimary),
          greaterThanOrEqualTo(7),
        );
        expect(
          contrastRatio(tokens.errorForeground, tokens.error),
          greaterThanOrEqualTo(7),
        );
      });

      test('$name: warning and success are 4.5:1 on every surface', () {
        for (final accent in [tokens.warning, tokens.success]) {
          for (final surface in surfaces.entries) {
            expect(
              contrastRatio(accent, surface.value),
              greaterThanOrEqualTo(4.5),
              reason: '$accent on ${surface.key}',
            );
          }
        }
      });

      test('$name: borders are 3:1 on every surface', () {
        for (final border in [tokens.border, tokens.chromeBorder]) {
          for (final surface in surfaces.entries) {
            expect(
              contrastRatio(border, surface.value),
              greaterThanOrEqualTo(3),
              reason: 'border on ${surface.key}',
            );
          }
        }
      });

      test('$name: the focus ring is at least three pixels', () {
        expect(tokens.focusRingWidth, greaterThanOrEqualTo(3));
      });

      test('$name: copyWith round-trips to an equal value', () {
        expect(tokens.copyWith(), tokens);
        expect(tokens.copyWith().hashCode, tokens.hashCode);
      });
    }

    test('focusRingWidth takes part in copyWith, equality and lerp', () {
      final edited = QuarkTokens.dark.copyWith(focusRingWidth: 5);
      expect(edited.focusRingWidth, 5);
      expect(edited, isNot(QuarkTokens.dark));
      expect(QuarkTokens.dark.lerp(edited, 0.5).focusRingWidth, 3.5);
    });
  });
}

/// A color no token has, to tell an edited field from the rest.
const Color _marker = Color(0xFF123456);
