import 'dart:math' as math;

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
        expect(scheme.outline, tokens.outline);
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
      test('$name: the error foreground contrasts with the error fill', () {
        final scheme = QuarkTheme.from(tokens, brightness).colorScheme;
        expect(
          contrastRatio(scheme.onError, scheme.error),
          greaterThanOrEqualTo(4.5),
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

    test('dark() and light() are from() with the shipped tokens', () {
      expect(
        QuarkTheme.dark().colorScheme,
        QuarkTheme.from(QuarkTokens.dark, Brightness.dark).colorScheme,
      );
      expect(
        QuarkTheme.light().colorScheme,
        QuarkTheme.from(QuarkTokens.light, Brightness.light).colorScheme,
      );
      expect(QuarkTheme.dark().extension<QuarkTokens>(), QuarkTokens.dark);
      expect(QuarkTheme.light().extension<QuarkTokens>(), QuarkTokens.light);
    });
  });

  /// #2600: WCAG 2.1 AA asks 4.5:1 of text (1.4.3) and 3:1 of the edges and
  /// indicators a user needs to find a control (1.4.11). White on the sky-500
  /// primary was 2.77:1, and dark's muted text 2.4:1.
  group('the tokens meet WCAG AA', () {
    for (final (name, tokens) in [
      ('dark', QuarkTokens.dark),
      ('light', QuarkTokens.light),
    ]) {
      final surfaces = {
        'background': tokens.background,
        'card': tokens.card,
        'sidebar': tokens.sidebar,
        'input': tokens.input,
      };
      final text = {
        'foreground': tokens.foreground,
        'cardForeground': tokens.cardForeground,
        'secondaryForeground': tokens.secondaryForeground,
        'mutedForeground': tokens.mutedForeground,
        'primary': tokens.primary,
        'error': tokens.error,
        'warning': tokens.warning,
        'success': tokens.success,
      };

      for (final MapEntry(key: fg, value: fgColor) in text.entries) {
        for (final MapEntry(key: bg, value: bgColor) in surfaces.entries) {
          test('$name: $fg on $bg is at least 4.5:1', () {
            expect(contrastRatio(fgColor, bgColor), greaterThanOrEqualTo(4.5));
          });
        }
      }

      for (final MapEntry(key: bg, value: bgColor) in surfaces.entries) {
        test('$name: outline on $bg is at least 3:1', () {
          expect(
            contrastRatio(tokens.outline, bgColor),
            greaterThanOrEqualTo(3.0),
          );
        });
      }

      test('$name: primaryForeground on primary is at least 4.5:1', () {
        expect(
          contrastRatio(tokens.primaryForeground, tokens.primary),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
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

      test('$name: a focused icon button wears the same outline', () {
        final side = QuarkTheme.from(
          tokens,
          brightness,
        ).iconButtonTheme.style!.side!;

        final focused = side.resolve({WidgetState.focused})!;
        expect(focused.color, tokens.primary);
        expect(focused.width, 2);
        expect(side.resolve(<WidgetState>{}), isNull);
      });

      test('$name: ink and list tiles tint strongly under focus', () {
        final theme = QuarkTheme.from(tokens, brightness);

        expect(theme.focusColor.a, closeTo(QuarkTheme.focusAlpha, 0.01));
        expect(
          theme.focusColor.withValues(alpha: 1),
          tokens.primary.withValues(alpha: 1),
        );
        // Material's own default is 0.12, which is what was too faint.
        expect(QuarkTheme.focusAlpha, greaterThan(0.12 * 2));
      });

      test('$name: switches, checkboxes and radios show a strong halo', () {
        final theme = QuarkTheme.from(tokens, brightness);

        for (final overlay in [
          theme.switchTheme.overlayColor,
          theme.checkboxTheme.overlayColor,
          theme.radioTheme.overlayColor,
        ]) {
          final focused = overlay!.resolve({WidgetState.focused})!;
          expect(focused.a, closeTo(QuarkTheme.focusAlpha, 0.01));
          // Hover and press keep Material's defaults.
          expect(overlay.resolve({WidgetState.hovered}), isNull);
        }
        final box = theme.checkboxTheme.side! as WidgetStateBorderSide;
        final focusedBox = box.resolve({WidgetState.focused})!;
        expect(focusedBox.width, 2);
        expect(focusedBox.color, tokens.primary);
      });
    }
  });
}

/// The WCAG contrast ratio between [a] and [b], from 1.0 to 21.0.
double contrastRatio(Color a, Color b) {
  final lighter = math.max(a.computeLuminance(), b.computeLuminance());
  final darker = math.min(a.computeLuminance(), b.computeLuminance());
  return (lighter + 0.05) / (darker + 0.05);
}
