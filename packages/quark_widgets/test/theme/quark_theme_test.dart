import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  group('QuarkTheme.from', () {
    for (final (name, tokens, brightness) in [
      ('dark', QuarkTokens.dark, Brightness.dark),
      ('light', QuarkTokens.light, Brightness.light),
    ]) {
      test('$name: the color scheme matches the tokens', () {
        final theme = QuarkTheme.from(tokens, brightness);
        final scheme = theme.colorScheme;

        expect(theme.brightness, brightness);
        expect(scheme.brightness, brightness);
        expect(scheme.primary, tokens.primary);
        expect(scheme.onPrimary, tokens.primaryForeground);
        expect(scheme.surface, tokens.card);
        expect(scheme.onSurface, tokens.foreground);
        expect(scheme.secondary, tokens.sidebar);
        expect(scheme.onSecondary, tokens.secondaryForeground);
        expect(scheme.error, tokens.error);
        expect(scheme.onError, tokens.errorForeground);
        expect(scheme.outline, tokens.border);
        expect(scheme.outlineVariant, tokens.border);
        expect(theme.scaffoldBackgroundColor, tokens.background);
      });

      test('$name: the tokens ride along as a theme extension', () {
        final theme = QuarkTheme.from(tokens, brightness);
        expect(theme.extension<QuarkTokens>(), tokens);
      });

      // #1789: dark's errorForeground was red-300, a tint of the error fill it
      // sits on. At 1.98:1 the label on an enabled destructive button read as
      // the disabled gray it had just stopped being.
      // #2523: white on sky 500 was 2.77:1 on every filled button, and the
      // same blue as text on a light card was no better.
      test('$name: the primary pair is legible', () {
        final scheme = QuarkTheme.from(tokens, brightness).colorScheme;
        expect(
          contrastRatio(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        for (final surface in [tokens.background, tokens.card]) {
          expect(
            contrastRatio(scheme.primary, surface),
            greaterThanOrEqualTo(4.5),
          );
        }
      });

      test('$name: the error foreground contrasts with the error fill', () {
        final scheme = QuarkTheme.from(tokens, brightness).colorScheme;
        expect(
          contrastRatio(scheme.onError, scheme.error),
          greaterThanOrEqualTo(3.0),
        );
      });
    }

    test('edited tokens reach the theme', () {
      final edited = QuarkTokens.dark.copyWith(
        primary: const Color(0xFFAA0000),
        background: const Color(0xFF010203),
        radiusLg: 21,
      );
      final theme = QuarkTheme.from(edited, Brightness.dark);

      expect(theme.colorScheme.primary, const Color(0xFFAA0000));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF010203));
      expect(
        theme.cardTheme.shape,
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(21),
          side: BorderSide(color: edited.border),
        ),
      );
    });

    test('a theme color builds the whole theme from its tokens', () {
      for (final themeColor in [
        QuarkThemeColor.violet,
        QuarkThemeColor.fromSeed(const Color(0xFF00AA55)),
      ]) {
        for (final (theme, brightness) in [
          (QuarkTheme.light(themeColor: themeColor), Brightness.light),
          (QuarkTheme.dark(themeColor: themeColor), Brightness.dark),
        ]) {
          final tokens = themeColor.tokensFor(brightness);
          final classic = QuarkThemeColor.classic.tokensFor(brightness);
          expect(theme.brightness, brightness);
          expect(theme.extension<QuarkTokens>(), tokens);
          expect(theme.colorScheme.primary, tokens.primary);
          expect(theme.colorScheme.onPrimary, tokens.primaryForeground);
          expect(theme.colorScheme.surface, tokens.card);
          expect(theme.scaffoldBackgroundColor, tokens.background);
          // Not just the accent: the surfaces and the chrome move too.
          expect(tokens.background, isNot(classic.background));
          expect(tokens.card, isNot(classic.card));
          expect(tokens.chrome, isNot(classic.chrome));
          expect(
            theme.filledButtonTheme.style!.side!.resolve({
              WidgetState.focused,
            })!.color,
            tokens.primary,
          );
          expect(
            theme.switchTheme.thumbColor!.resolve({WidgetState.selected}),
            tokens.primary,
          );
        }
      }
    });

    test('the app bar and the drawer are chrome, with its text color', () {
      for (final themeColor in [
        QuarkThemeColor.classic,
        QuarkThemeColor.pink,
      ]) {
        for (final brightness in Brightness.values) {
          final tokens = themeColor.tokensFor(brightness);
          final theme = QuarkTheme.from(tokens, brightness);
          expect(theme.appBarTheme.backgroundColor, tokens.chrome);
          expect(theme.appBarTheme.foregroundColor, tokens.chromeForeground);
          expect(theme.drawerTheme.backgroundColor, tokens.chrome);
          // Side panels in the content keep the content's recessed surface.
          expect(theme.colorScheme.secondary, tokens.sidebar);
        }
      }
    });

    // #2786: the surface containers were left to Material's seed-derived
    // tonal palette, so the docs toolbar, which is filled with
    // surfaceContainer, drifted from the chrome around it.
    test('the surface containers come from the tokens', () {
      for (final themeColor in [
        QuarkThemeColor.classic,
        QuarkThemeColor.pink,
        QuarkThemeColor.lime,
        QuarkThemeColor.fromSeed(const Color(0xFF00AA55)),
      ]) {
        for (final brightness in Brightness.values) {
          final tokens = themeColor.tokensFor(brightness);
          final scheme = QuarkTheme.from(tokens, brightness).colorScheme;
          final id = '${themeColor.storageValue} in ${brightness.name}';
          expect(scheme.surfaceContainerLowest, tokens.background, reason: id);
          expect(scheme.surfaceContainerLow, tokens.sidebar, reason: id);
          expect(scheme.surfaceContainer, tokens.chrome, reason: id);
          expect(scheme.surfaceContainerHigh, tokens.card, reason: id);
          expect(
            scheme.surfaceContainerHighest,
            Color.alphaBlend(
              tokens.foreground.withValues(alpha: 0.08),
              tokens.card,
            ),
            reason: id,
          );
          // The well a filled field or a header cell is drawn in stays
          // readable and set off from the card it sits on.
          expect(
            contrastRatio(tokens.foreground, scheme.surfaceContainerHighest),
            greaterThanOrEqualTo(4.5),
            reason: id,
          );
          expect(
            scheme.surfaceContainerHighest,
            isNot(tokens.card),
            reason: id,
          );
        }
      }
    });

    test('classic is the shipped tokens', () {
      // What the app bar and the drawer were before they had a token.
      expect(
        QuarkTheme.light(
          themeColor: QuarkThemeColor.classic,
        ).appBarTheme.backgroundColor,
        QuarkTokens.light.sidebar,
      );
      expect(
        QuarkTheme.dark(
          themeColor: QuarkThemeColor.classic,
        ).appBarTheme.foregroundColor,
        QuarkTokens.dark.foreground,
      );
    });

    test('classic dark() and light() are from() with the shipped tokens', () {
      expect(
        QuarkTheme.dark(themeColor: QuarkThemeColor.classic).colorScheme,
        QuarkTheme.from(QuarkTokens.dark, Brightness.dark).colorScheme,
      );
      expect(
        QuarkTheme.light(themeColor: QuarkThemeColor.classic).colorScheme,
        QuarkTheme.from(QuarkTokens.light, Brightness.light).colorScheme,
      );
      expect(
        QuarkTheme.dark(
          themeColor: QuarkThemeColor.classic,
        ).extension<QuarkTokens>(),
        QuarkTokens.dark,
      );
      expect(
        QuarkTheme.light(
          themeColor: QuarkThemeColor.classic,
        ).extension<QuarkTokens>(),
        QuarkTokens.light,
      );
    });
  });

  /// #2028: a keyboard user had nothing to tell them where they were. The
  /// focused field differed from a resting one only in hue, and buttons
  /// carried Material's default focus tint, which on a filled button sits on
  /// top of a color it barely differs from.
  group('keyboard focus is visible', () {
    for (final (name, tokens, brightness) in [
      ('dark', QuarkTokens.dark, Brightness.dark),
      ('light', QuarkTokens.light, Brightness.light),
    ]) {
      test('$name: a focused field is thicker, not just another color', () {
        final decoration = QuarkTheme.from(
          tokens,
          brightness,
        ).inputDecorationTheme;

        final focused = decoration.focusedBorder! as OutlineInputBorder;
        final resting = decoration.enabledBorder! as OutlineInputBorder;
        expect(focused.borderSide.color, tokens.primary);
        expect(focused.borderSide.width, greaterThan(resting.borderSide.width));
      });

      test('$name: a focused button wears an outline', () {
        final theme = QuarkTheme.from(tokens, brightness);

        for (final style in [
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
          // #2604: a bare icon button had only Material's faint tint.
          theme.iconButtonTheme.style,
        ]) {
          final side = style!.side!;
          final focused = side.resolve({WidgetState.focused});
          expect(focused, isNotNull);
          expect(focused!.color, tokens.primary);
          expect(focused.width, 2);
          // And nothing extra while it is merely sitting there.
          final resting = side.resolve(<WidgetState>{});
          expect(resting?.width ?? 0, lessThan(2));
        }
      });
    }
  });
}
