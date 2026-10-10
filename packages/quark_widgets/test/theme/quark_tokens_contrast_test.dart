import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The ratio WCAG AA asks of text (1.4.3).
const double _text = 4.5;

/// The ratio WCAG asks of a boundary that identifies a control (1.4.11).
const double _boundary = 3;

/// The strongest wash of [QuarkTokens.warning] a widget lays under text drawn
/// in it: the calendar's reminder banner and upcoming badge.
const double _warningTint = 0.16;

/// How strongly a selected chip, segment or badge is tinted with the accent
/// its label is drawn in.
const double _selectionTint = 0.12;

/// #2600: every foreground the shipped token sets draw on a surface, measured
/// against every surface it is drawn on, in both themes.
void main() {
  for (final (name, tokens, brightness) in [
    ('dark', QuarkTokens.dark, Brightness.dark),
    ('light', QuarkTokens.light, Brightness.light),
    // #3071: the high-contrast set of every preset, `classic` being the
    // shipped pair.
    for (final themeColor in QuarkThemeColor.presets)
      for (final brightness in Brightness.values)
        (
          'high-contrast ${themeColor.storageValue} ${brightness.name}',
          themeColor.tokensFor(brightness, highContrast: true),
          brightness,
        ),
  ]) {
    group(name, () {
      final content = {
        'background': tokens.background,
        'card': tokens.card,
        'sidebar': tokens.sidebar,
        'input': tokens.input,
      };
      final chrome = {'chrome': tokens.chrome, 'bar button': tokens.input};

      void expectRatio(
        String label,
        Color color,
        Map<String, Color> surfaces,
        double ratio,
      ) {
        for (final MapEntry(key: surface, value: on) in surfaces.entries) {
          expect(
            contrastRatio(color, on),
            greaterThanOrEqualTo(ratio),
            reason: '$name: $label on $surface',
          );
        }
      }

      /// [surfaces] and each of them washed with [color] at [alpha].
      Map<String, Color> withTint(
        Color color,
        Map<String, Color> surfaces,
        double alpha,
      ) => {
        ...surfaces,
        for (final MapEntry(key: surface, value: on) in surfaces.entries)
          'tinted $surface': Color.alphaBlend(
            color.withValues(alpha: alpha),
            on,
          ),
      };

      test('text is 4.5:1 on every content surface', () {
        for (final (label, color) in [
          ('foreground', tokens.foreground),
          ('cardForeground', tokens.cardForeground),
          ('secondaryForeground', tokens.secondaryForeground),
          ('mutedForeground', tokens.mutedForeground),
        ]) {
          expectRatio(label, color, content, _text);
        }
      });

      test('chrome text is 4.5:1 on the chrome and a bar button', () {
        for (final (label, color) in [
          ('chromeForeground', tokens.chromeForeground),
          ('chromeSecondaryForeground', tokens.chromeSecondaryForeground),
          ('chromeMutedForeground', tokens.chromeMutedForeground),
        ]) {
          expectRatio(label, color, chrome, _text);
        }
      });

      test('the accent is 4.5:1 as text, selected chips included', () {
        expectRatio(
          'primary',
          tokens.primary,
          withTint(tokens.primary, content, _selectionTint),
          _text,
        );
        expectRatio(
          'chromePrimary',
          tokens.chromePrimary,
          withTint(tokens.chromePrimary, {
            ...content,
            ...chrome,
          }, _selectionTint),
          _text,
        );
      });

      test('status colors are 4.5:1 as text', () {
        expectRatio('error', tokens.error, content, _text);
        expectRatio('success', tokens.success, content, _text);
        expectRatio(
          'warning',
          tokens.warning,
          withTint(tokens.warning, content, _warningTint),
          _text,
        );
      });

      test('text on a fill is 4.5:1 on that fill', () {
        expectRatio('primaryForeground', tokens.primaryForeground, {
          'primary': tokens.primary,
          'chromePrimary': tokens.chromePrimary,
        }, _text);
        expectRatio('errorForeground', tokens.errorForeground, {
          'error': tokens.error,
        }, _text);
      });

      test('control outlines and the focus ring are 3:1', () {
        expectRatio('outline', tokens.outline, content, _boundary);
        // The focus ring is drawn in the accent wherever a control sits.
        expectRatio('focus ring', tokens.primary, {
          ...content,
          'chrome': tokens.chrome,
        }, _boundary);
        // `border` and `chromeBorder` are decorative hairlines, which 1.4.11
        // exempts: a bar button is told apart by its glyph, not its edge.
      });

      test('the theme draws control boundaries in the outline', () {
        final theme = QuarkTheme.from(tokens, brightness);
        final decoration = theme.inputDecorationTheme;
        for (final border in [decoration.border, decoration.enabledBorder]) {
          expect(
            (border! as OutlineInputBorder).borderSide.color,
            tokens.outline,
          );
        }
        expect(theme.checkboxTheme.side!.color, tokens.outline);
        expect(theme.colorScheme.outline, tokens.outline);
        expect(theme.colorScheme.outlineVariant, tokens.border);
      });

      test('a switch is 3:1 against the surface, on and off', () {
        final switchTheme = QuarkTheme.from(tokens, brightness).switchTheme;
        const on = {WidgetState.selected};
        const off = <WidgetState>{};
        Color resolve(
          WidgetStateProperty<Color?>? property,
          Set<WidgetState> s,
        ) => property!.resolve(s)!;

        // On: the track stands out from the surface, the thumb from the track.
        final onTrack = resolve(switchTheme.trackColor, on);
        expectRatio('on track', onTrack, content, _boundary);
        expect(
          contrastRatio(resolve(switchTheme.thumbColor, on), onTrack),
          greaterThanOrEqualTo(_boundary),
          reason: '$name: on thumb on its track',
        );

        // Off: the outline marks the track, and the thumb stands out from it.
        expectRatio(
          'off track outline',
          resolve(switchTheme.trackOutlineColor, off),
          content,
          _boundary,
        );
        expect(
          contrastRatio(
            resolve(switchTheme.thumbColor, off),
            resolve(switchTheme.trackColor, off),
          ),
          greaterThanOrEqualTo(_boundary),
          reason: '$name: off thumb on its track',
        );
      });
    });
  }

  test('outline takes part in copyWith, equality and lerp', () {
    const marker = Color(0xFF123456);
    final edited = QuarkTokens.light.copyWith(outline: marker);
    expect(edited.outline, marker);
    expect(edited, isNot(QuarkTokens.light));
    expect(edited.hashCode, isNot(QuarkTokens.light.hashCode));
    expect(QuarkTokens.light.lerp(edited, 1).outline, marker);
    expect(QuarkTokens.light.lerp(edited, 0.5).outline, isNot(marker));
  });
}
