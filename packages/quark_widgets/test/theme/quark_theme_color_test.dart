import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The ratio WCAG AA asks of text.
const double _aa = 4.5;

/// The ratio WCAG asks of a boundary that identifies a control.
const double _boundary = 3;

/// How far above a WCAG ratio a derived pair has to land, so none sits on
/// the floor where a rounding step fails it (#2785).
const double _margin = 0.1;

/// How strongly a selected chip, segment or badge is tinted with the accent
/// its label is drawn in.
const double _selectionTint = 0.12;

/// Custom seeds from all around the wheel, at several saturations and
/// lightness levels, plus the three with no hue at all.
final List<Color> _seeds = [
  for (var hue = 0.0; hue < 360; hue += 15)
    for (final saturation in [0.15, 0.5, 0.75, 1.0])
      for (final lightness in [0.1, 0.3, 0.5, 0.7, 0.9])
        HSLColor.fromAHSL(1, hue, saturation, lightness).toColor(),
  const Color(0xFFFFFFFF),
  const Color(0xFF000000),
  const Color(0xFF808080),
];

/// Every derived theme color: the presets but `classic`, and the seeds.
final List<QuarkThemeColor> _derived = [
  for (final preset in QuarkThemeColor.presets)
    if (preset != QuarkThemeColor.classic) preset,
  for (final seed in _seeds) QuarkThemeColor.fromSeed(seed),
];

/// The derived theme colors with a hue of their own to keep: the seed is at
/// least half saturated, which is where the derivation stops fading to gray.
final List<QuarkThemeColor> _chromatic = [
  for (final themeColor in _derived)
    if (HSLColor.fromColor(themeColor.seed!).saturation >= 0.5) themeColor,
];

/// The hue of [color] on the HSL wheel, in degrees.
double _hue(Color color) => HSLColor.fromColor(color).hue;

/// The shorter way around the wheel between two hues, in degrees.
double _hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// How colorful [color] is, from 0 (gray) to 1: the spread of its channels.
double _chroma(Color color) =>
    [color.r, color.g, color.b].reduce(math.max) -
    [color.r, color.g, color.b].reduce(math.min);

/// The surfaces content is drawn on.
Map<String, Color> _content(QuarkTokens tokens) => {
  'background': tokens.background,
  'card': tokens.card,
  'input': tokens.input,
  'sidebar': tokens.sidebar,
};

/// The surfaces a widget on the chrome is drawn on: the chrome itself, and
/// the input fill of a bar button.
Map<String, Color> _chromeSurfaces(QuarkTokens tokens) => {
  'chrome': tokens.chrome,
  'bar button': tokens.input,
};

/// The theme color an admin or a person picks (#2740): every preset and any
/// custom seed has to yield a legible theme in both modes, and one that is
/// still visibly the color that was picked.
void main() {
  group('contrast', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;
      final classic = QuarkThemeColor.classic.tokensFor(brightness);

      void expectRatio(
        String label,
        Color color,
        Map<String, Color> surfaces,
        double ratio, {
        double margin = 0,
      }) {
        expect(color.a, 1.0, reason: '$label is opaque');
        for (final MapEntry(key: name, value: surface) in surfaces.entries) {
          expect(
            contrastRatio(color, surface),
            greaterThanOrEqualTo(ratio + margin),
            reason: '$label on $name',
          );
        }
      }

      /// The accent is text on a surface and on that surface tinted with
      /// itself, which is how a selected chip is drawn.
      void expectAccent(String label, Color accent, Map<String, Color> on) {
        final tint = accent.withValues(alpha: _selectionTint);
        expectRatio(
          label,
          accent,
          {
            ...on,
            for (final MapEntry(key: name, value: surface) in on.entries)
              'selected $name': Color.alphaBlend(tint, surface),
          },
          _aa,
          margin: _margin,
        );
      }

      /// The worst a status color scores on the classic content surfaces.
      double classicWorst(Color status) => _content(classic).values
          .map((surface) => contrastRatio(status, surface))
          .reduce(math.min);

      void expectLegible(QuarkThemeColor themeColor) {
        final tokens = themeColor.tokensFor(brightness);
        final id = '${themeColor.storageValue} in $mode';
        final content = _content(tokens);
        final chrome = _chromeSurfaces(tokens);

        // Text on content.
        for (final (name, color) in [
          ('foreground', tokens.foreground),
          ('cardForeground', tokens.cardForeground),
          ('secondaryForeground', tokens.secondaryForeground),
          ('mutedForeground', tokens.mutedForeground),
        ]) {
          expectRatio('$id: $name', color, content, _aa, margin: _margin);
        }
        // Text on chrome.
        for (final (name, color) in [
          ('chromeForeground', tokens.chromeForeground),
          ('chromeSecondaryForeground', tokens.chromeSecondaryForeground),
          ('chromeMutedForeground', tokens.chromeMutedForeground),
        ]) {
          expectRatio('$id: $name', color, chrome, _aa, margin: _margin);
        }

        // The accent: text on content, a shape on chrome, and its own
        // counterpart for text on chrome.
        expectAccent('$id: primary', tokens.primary, content);
        expectRatio(
          '$id: primary',
          tokens.primary,
          {'chrome': tokens.chrome},
          _boundary,
          margin: _margin,
        );
        expectAccent('$id: chromePrimary', tokens.chromePrimary, {
          ...content,
          ...chrome,
        });
        expectRatio('$id: primaryForeground', tokens.primaryForeground, {
          'primary': tokens.primary,
          'chromePrimary': tokens.chromePrimary,
        }, _aa);

        // Outlines.
        expectRatio(
          '$id: border',
          tokens.border,
          content,
          _boundary,
          margin: _margin,
        );
        expectRatio(
          '$id: chromeBorder',
          tokens.chromeBorder,
          {'chrome': tokens.chrome},
          _boundary,
          margin: _margin,
        );

        // Status colors are fixed. Dark surfaces give them 3:1; white does
        // not (warning is 2.15:1 and success 2.54:1 on a classic light card,
        // 1.96 and 2.32 on the classic light sidebar), so tinted surfaces are
        // held to scoring no worse than the classic ones do.
        for (final (name, status) in [
          ('error', tokens.error),
          ('warning', tokens.warning),
          ('success', tokens.success),
        ]) {
          expectRatio(
            '$id: $name',
            status,
            content,
            math.min(_boundary, classicWorst(status)),
          );
        }

        // What `onChrome` hands a widget in the bar is the same colors.
        final onChrome = tokens.onChrome;
        expect(onChrome.foreground, tokens.chromeForeground);
        expect(onChrome.cardForeground, tokens.chromeForeground);
        expect(onChrome.secondaryForeground, tokens.chromeSecondaryForeground);
        expect(onChrome.mutedForeground, tokens.chromeMutedForeground);
        expect(onChrome.border, tokens.chromeBorder);
        expect(onChrome.primary, tokens.chromePrimary);
        expect(onChrome.input, tokens.input);
        expect(onChrome.chrome, tokens.chrome);
      }

      test('$mode: every derived preset is legible', () {
        final presets = _derived.where((themeColor) => !themeColor.isCustom);
        expect(presets, hasLength(QuarkThemeColor.presets.length - 1));
        presets.forEach(expectLegible);
      });

      test('$mode: every custom seed is legible', () {
        expect(_seeds, hasLength(483));
        for (final seed in _seeds) {
          expectLegible(QuarkThemeColor.fromSeed(seed));
        }
      });

      // Classic is written out by hand rather than derived, and #2600 still
      // tracks its border. Text, muted text included (#2785), and the accent
      // are held to AA on every surface they are drawn on.
      test('$mode: classic text and accent clear AA', () {
        final content = _content(classic);
        final chrome = _chromeSurfaces(classic);
        expectRatio('classic: mutedForeground', classic.mutedForeground, {
          ...content,
          ...chrome,
        }, _aa);
        expectRatio(
          'classic: chromeMutedForeground',
          classic.chromeMutedForeground,
          chrome,
          _aa,
        );
        for (final (name, accent, on) in [
          ('primary', classic.primary, content),
          ('chromePrimary', classic.chromePrimary, {...content, ...chrome}),
        ]) {
          final tint = accent.withValues(alpha: _selectionTint);
          expectRatio('classic: $name', accent, {
            ...on,
            for (final MapEntry(key: surface, value: color) in on.entries)
              'selected $surface': Color.alphaBlend(tint, color),
          }, _aa);
        }
        expectRatio('classic: primary', classic.primary, {
          'chrome': classic.chrome,
        }, _boundary);
        expectRatio('classic: primaryForeground', classic.primaryForeground, {
          'primary': classic.primary,
        }, _aa);
      });

      test(
        '$mode: the Material slots the theme leaves seeded stay legible',
        () {
          for (final themeColor in _derived) {
            final tokens = themeColor.tokensFor(brightness);
            final scheme = QuarkTheme.from(tokens, brightness).colorScheme;
            final id = '${themeColor.storageValue} in $mode';
            expectRatio('$id: onSurfaceVariant', scheme.onSurfaceVariant, {
              ..._content(tokens),
              'surfaceContainerHighest': scheme.surfaceContainerHighest,
            }, _aa);
            expectRatio('$id: onSurface', scheme.onSurface, {
              'surfaceContainerHighest': scheme.surfaceContainerHighest,
            }, _aa);
            expectRatio('$id: onPrimaryContainer', scheme.onPrimaryContainer, {
              'primaryContainer': scheme.primaryContainer,
            }, _aa);
            expectRatio('$id: onErrorContainer', scheme.onErrorContainer, {
              'errorContainer': scheme.errorContainer,
            }, _aa);
          }
        },
      );

      test('$mode: presets keep clear of the status colors and each other', () {
        // A near-neutral preset has no hue to confuse with anything, and
        // classic is not derived.
        final hues = {
          for (final preset in _chromatic)
            if (!preset.isCustom)
              preset.name!: _hue(preset.tokensFor(brightness).primary),
        };
        expect(hues.keys, isNot(contains('graphite')));
        expect(hues, hasLength(QuarkThemeColor.presets.length - 2));
        final status = {
          'error': _hue(classic.error),
          'warning': _hue(classic.warning),
          'success': _hue(classic.success),
        };

        for (final MapEntry(key: name, value: hue) in hues.entries) {
          for (final MapEntry(key: token, value: taken) in status.entries) {
            expect(
              _hueDistance(hue, taken),
              greaterThanOrEqualTo(25),
              reason: '$name is too close to $token',
            );
          }
          for (final MapEntry(key: other, value: otherHue) in hues.entries) {
            if (other == name) continue;
            expect(
              _hueDistance(hue, otherHue),
              greaterThanOrEqualTo(25),
              reason: '$name is too close to $other',
            );
          }
        }
      });
    }
  });

  // A derivation could pass every ratio above by turning everything gray.
  // These hold it to the design: colored chrome, tinted content.
  group('design intent', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;
      final classic = QuarkThemeColor.classic.tokensFor(brightness);

      test('$mode: the chrome and the accent keep the hue that was picked', () {
        for (final themeColor in _chromatic) {
          final tokens = themeColor.tokensFor(brightness);
          final hue = _hue(themeColor.seed!);
          for (final (name, color) in [
            ('chrome', tokens.chrome),
            ('primary', tokens.primary),
            ('chromePrimary', tokens.chromePrimary),
          ]) {
            expect(
              _hueDistance(_hue(color), hue),
              lessThan(3),
              reason: '${themeColor.storageValue} in $mode: $name',
            );
          }
        }
      });

      test('$mode: the chrome is visibly colored and set off from content', () {
        for (final themeColor in _chromatic) {
          final tokens = themeColor.tokensFor(brightness);
          final id = '${themeColor.storageValue} in $mode';
          expect(
            _chroma(tokens.chrome),
            greaterThanOrEqualTo(_chromaFloor[brightness]!),
            reason: '$id: chrome is too gray',
          );
          expect(
            _chroma(tokens.chrome),
            greaterThan(2 * _chroma(tokens.background)),
            reason: '$id: chrome is no more colorful than the page',
          );
          expect(
            contrastRatio(tokens.chrome, tokens.background),
            greaterThanOrEqualTo(1.2),
            reason: '$id: chrome blends into the page',
          );
        }
      });

      test('$mode: content surfaces stay near the classic ones, tinted', () {
        for (final themeColor in _derived) {
          final tokens = themeColor.tokensFor(brightness);
          final id = '${themeColor.storageValue} in $mode';
          final shipped = _content(classic);
          for (final MapEntry(key: name, value: surface) in _content(
            tokens,
          ).entries) {
            expect(
              HSLColor.fromColor(surface).lightness,
              closeTo(HSLColor.fromColor(shipped[name]!).lightness, 0.03),
              reason: '$id: $name',
            );
            expect(
              _chroma(surface),
              // The classic dark input, `#131C2E`, spreads 0.106.
              lessThanOrEqualTo(0.12),
              reason: '$id: $name is more than a tint',
            );
          }
        }
        for (final themeColor in _chromatic) {
          expect(
            _chroma(themeColor.tokensFor(brightness).background),
            greaterThan(0),
            reason: '${themeColor.storageValue} in $mode: no tint',
          );
        }
      });

      test('$mode: only color moves', () {
        for (final themeColor in _derived) {
          final tokens = themeColor.tokensFor(brightness);
          expect(tokens.error, classic.error);
          expect(tokens.errorForeground, classic.errorForeground);
          expect(tokens.warning, classic.warning);
          expect(tokens.success, classic.success);
          expect(tokens.eventColors, classic.eventColors);
          expect(tokens.radiusMd, classic.radiusMd);
          expect(tokens.spacingMd, classic.spacingMd);
        }
      });
    }

    test('the light and dark sets of one color share a hue', () {
      for (final themeColor in _chromatic) {
        final light = themeColor.tokensFor(Brightness.light);
        final dark = themeColor.tokensFor(Brightness.dark);
        for (final (name, a, b) in [
          ('chrome', light.chrome, dark.chrome),
          ('primary', light.primary, dark.primary),
        ]) {
          expect(
            _hueDistance(_hue(a), _hue(b)),
            lessThan(4),
            reason: '${themeColor.storageValue}: $name',
          );
        }
        expect(light, isNot(dark));
      }
    });

    test('a seed with no hue yields a gray theme', () {
      for (final brightness in Brightness.values) {
        final tokens = QuarkThemeColor.fromSeed(
          const Color(0xFF808080),
        ).tokensFor(brightness);
        expect(_chroma(tokens.chrome), 0);
        expect(_chroma(tokens.primary), 0);
        expect(_chroma(tokens.background), 0);
      }
    });

    test('lightness and alpha of the seed do not change the hue it yields', () {
      final tokens = QuarkThemeColor.fromSeed(
        const Color(0xFF0369A1),
      ).tokensFor(Brightness.light);
      expect(
        QuarkThemeColor.fromSeed(const Color(0x220369A1)),
        QuarkThemeColor.fromSeed(const Color(0xFF0369A1)),
      );
      expect(
        _hueDistance(_hue(tokens.chrome), _hue(const Color(0xFF0369A1))),
        lessThan(3),
      );
    });
  });

  // The pairs #2785 measured, as it listed them: classic muted text failing
  // AA outright, and derived pairs sitting on the floor of their ratio.
  group('#2785', () {
    QuarkTokens tokens(QuarkThemeColor themeColor, Brightness brightness) =>
        themeColor.tokensFor(brightness);

    test('classic muted text clears AA on the surfaces that failed it', () {
      for (final (brightness, surfaces) in [
        (
          Brightness.dark,
          const [
            Color(0xFF070D19),
            Color(0xFF0F172A),
            Color(0xFF0C1220),
            Color(0xFF131C2E),
          ],
        ),
        (
          Brightness.light,
          const [Color(0xFFF1F5F9), Color(0xFFF8FAFC), Color(0xFFFFFFFF)],
        ),
      ]) {
        final classic = tokens(QuarkThemeColor.classic, brightness);
        // The surfaces are the shipped ones the issue measured against.
        expect({
          ..._content(classic).values,
          ..._chromeSurfaces(classic).values,
        }, containsAll(surfaces));
        for (final surface in surfaces) {
          for (final (name, muted) in [
            ('mutedForeground', classic.mutedForeground),
            ('chromeMutedForeground', classic.chromeMutedForeground),
          ]) {
            expect(
              contrastRatio(muted, surface),
              greaterThanOrEqualTo(_aa),
              reason: 'classic ${brightness.name}: $name on $surface',
            );
          }
        }
      }
    });

    test('the accent edge on light chrome is off the 3:1 floor', () {
      for (final preset in [
        QuarkThemeColor.blue,
        QuarkThemeColor.graphite,
        QuarkThemeColor.lime,
        QuarkThemeColor.magenta,
        QuarkThemeColor.pink,
      ]) {
        final light = tokens(preset, Brightness.light);
        expect(
          contrastRatio(light.primary, light.chrome),
          greaterThanOrEqualTo(_boundary + _margin),
          reason: preset.name,
        );
      }
    });

    test('derived light muted text is off the 4.5:1 floor', () {
      for (final preset in [
        QuarkThemeColor.indigo,
        QuarkThemeColor.violet,
        QuarkThemeColor.magenta,
        QuarkThemeColor.pink,
      ]) {
        final light = tokens(preset, Brightness.light);
        for (final (name, muted, surfaces) in [
          ('mutedForeground', light.mutedForeground, _content(light)),
          (
            'chromeMutedForeground',
            light.chromeMutedForeground,
            _chromeSurfaces(light),
          ),
        ]) {
          for (final MapEntry(key: surface, value: color) in surfaces.entries) {
            expect(
              contrastRatio(muted, color),
              greaterThanOrEqualTo(_aa + _margin),
              reason: '${preset.name}: $name on $surface',
            );
          }
        }
      }
    });
  });

  group('classic', () {
    test('is the shipped tokens, untouched', () {
      expect(
        QuarkThemeColor.classic.tokensFor(Brightness.light),
        same(QuarkTokens.light),
      );
      expect(
        QuarkThemeColor.classic.tokensFor(Brightness.dark),
        same(QuarkTokens.dark),
      );
      expect(QuarkThemeColor.presets.first, QuarkThemeColor.classic);
      expect(QuarkThemeColor.classic.seed, isNull);
    });

    test('draws its chrome exactly as its content was drawn before', () {
      for (final tokens in [QuarkTokens.light, QuarkTokens.dark]) {
        expect(tokens.onChrome, tokens);
        expect(tokens.chrome, tokens.sidebar);
      }
    });
  });

  group('storage', () {
    test('a preset is stored as its name, which the backend accepts', () {
      final shape = RegExp(r'^[a-z][a-z0-9-]{0,31}$');
      for (final preset in QuarkThemeColor.presets) {
        expect(preset.isCustom, isFalse);
        expect(preset.storageValue, preset.name);
        expect(shape.hasMatch(preset.storageValue), isTrue);
        expect(preset.label, isNotEmpty);
        expect(QuarkThemeColor.parse(preset.storageValue), same(preset));
      }
      expect(QuarkThemeColor.presets.map((p) => p.name), [
        'classic',
        'blue',
        'indigo',
        'violet',
        'magenta',
        'pink',
        'lime',
        'graphite',
      ]);
    });

    test('a custom theme color is stored as its lowercase seed', () {
      final themeColor = QuarkThemeColor.fromSeed(const Color(0xFFAB12EF));
      expect(themeColor.isCustom, isTrue);
      expect(themeColor.name, isNull);
      expect(themeColor.seed, const Color(0xFFAB12EF));
      expect(themeColor.storageValue, '#ab12ef');
      expect(themeColor.label, 'Custom');
      expect(QuarkThemeColor.parse('#ab12ef'), themeColor);
      expect(QuarkThemeColor.parse('#AB12EF'), themeColor);
      expect(themeColor.hashCode, QuarkThemeColor.parse('#ab12ef').hashCode);
      expect(
        QuarkThemeColor.fromSeed(const Color(0xFF00000A)).storageValue,
        '#00000a',
      );
      expect('$themeColor', 'QuarkThemeColor(#ab12ef)');
    });

    test('anything else falls back to classic', () {
      for (final stored in [
        null,
        '',
        ' ',
        'teal-from-a-newer-client',
        'Blue',
        'Classic',
        '#abc',
        '#ab12ef0',
        '#ab12eg',
        'ab12ef',
        '#ab12ef ',
        'rgb(1, 2, 3)',
      ]) {
        expect(
          QuarkThemeColor.parse(stored),
          same(QuarkThemeColor.classic),
          reason: '"$stored"',
        );
      }
    });
  });
}

/// The least colorful the chrome of a hue may be: the spread of its channels,
/// out of 1. The chrome is calm on purpose (#2777), so the floor only keeps
/// it from going gray. Dark chrome is deep, and a deep color has less room
/// between its channels, so its floor is lower.
const Map<Brightness, double> _chromaFloor = {
  Brightness.light: 0.12,
  Brightness.dark: 0.07,
};
