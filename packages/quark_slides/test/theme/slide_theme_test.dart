import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

/// The WCAG contrast ratio of two opaque `0xAARRGGBB` colors.
double contrast(int a, int b) {
  double luminance(int argb) {
    double channel(int shift) {
      final c = ((argb >> shift) & 0xFF) / 255;
      return c <= 0.03928
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
  }

  final (l1, l2) = (luminance(a), luminance(b));
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('SlideColor roles', () {
    const accent = SlideColor.theme(ThemeColor.accent1);

    test('a role color is written and read as theme:<role>', () {
      expect(accent.toHex(), 'theme:accent1');
      expect(SlideColor.parse('theme:accent1'), accent);
      expect(
          SlideColor.parse('theme:background2').role, ThemeColor.background2);
    });

    test('a role this version does not know reads as text', () {
      expect(
        SlideColor.parse('theme:accent9'),
        const SlideColor.theme(ThemeColor.text),
      );
    });

    test('resolves against the theme it is drawn in', () {
      expect(accent.resolve(SlideThemes.dark), 0xFF7AA2FF);
      expect(accent.resolve(SlideThemes.warm), 0xFFC2410C);
      expect(accent.resolve(null), ThemeColor.accent1.fallback);
    });

    test('a literal color ignores the theme', () {
      const red = SlideColor(0xFFFF0000);
      expect(red.resolve(SlideThemes.dark), 0xFFFF0000);
      expect(red.isThemeColor, isFalse);
      expect(accent.isThemeColor, isTrue);
    });

    test('argb of a role is its light fallback, but it is not that literal',
        () {
      expect(accent.argb, 0xFF3366FF);
      expect(accent, isNot(const SlideColor(0xFF3366FF)));
      expect(accent, const SlideColor.theme(ThemeColor.accent1));
      expect(
        accent.hashCode,
        const SlideColor.theme(ThemeColor.accent1).hashCode,
      );
    });
  });

  group('built-in themes', () {
    test('there are five, with distinct ids, found by id', () {
      expect(SlideThemes.all.map((t) => t.id), [
        'light',
        'dark',
        'warm',
        'cool',
        'highContrast',
      ]);
      for (final theme in SlideThemes.all) {
        expect(SlideThemes.byId(theme.id), same(theme));
        expect(theme.name, isNotEmpty);
      }
      expect(SlideThemes.byId('themes/default'), isNull);
    });

    test('the light theme is the roles\' fallbacks', () {
      for (final role in ThemeColor.values) {
        expect(SlideThemes.light.colors[role], role.fallback);
      }
    });

    test('text reads against the background in every theme', () {
      for (final theme in SlideThemes.all) {
        final minimum = theme == SlideThemes.highContrast ? 7.0 : 4.5;
        final background = theme.colors[ThemeColor.background];
        for (final role in [ThemeColor.text, ThemeColor.text2]) {
          expect(
            contrast(theme.colors[role], background),
            greaterThanOrEqualTo(minimum),
            reason: '${theme.id} ${role.name}',
          );
        }
      }
    });

    test('each round trips through JSON', () {
      for (final theme in SlideThemes.all) {
        final json = jsonDecode(jsonEncode(theme.toJson()));
        expect(SlideTheme.fromJson(json, r'$'), theme, reason: theme.id);
      }
    });

    test('text styles by role, set in the heading or body font', () {
      final warm = SlideThemes.warm;
      expect(warm.textStyle(ThemeTextRole.title), warm.title);
      expect(warm.textStyle(ThemeTextRole.subtitle), warm.subtitle);
      expect(warm.textStyle(ThemeTextRole.body), warm.body);
      expect(warm.fontOf(warm.title), 'Georgia');
      expect(warm.fontOf(warm.body), isNull);
      expect(warm.title.fontSize, greaterThan(warm.body.fontSize));
    });
  });

  group('SlideTheme', () {
    test('copyWith replaces what it is given and keeps the rest', () {
      final custom = SlideThemes.cool.copyWith(
        id: 'ours',
        colors: SlideThemes.cool.colors.copyWith({
          ThemeColor.accent1: 0xFF123456,
        }),
        headingFont: 'Lora',
      );
      expect(custom.id, 'ours');
      expect(custom.name, 'Cool');
      expect(custom.colors[ThemeColor.accent1], 0xFF123456);
      expect(custom.colors[ThemeColor.accent2], 0xFF1D4ED8);
      expect(custom.headingFont, 'Lora');
      expect(custom.copyWith(headingFont: null).headingFont, isNull);
      expect(custom, isNot(SlideThemes.cool));
    });

    test('a palette that leaves a role out falls back to it', () {
      final palette = ThemePalette.fromJson({'text': '#112233'}, r'$');
      expect(palette[ThemeColor.text], 0xFF112233);
      expect(palette[ThemeColor.accent3], ThemeColor.accent3.fallback);
    });

    test('a theme with only an id reads with the default styles', () {
      final theme = SlideTheme.fromJson({'id': 'bare'}, r'$');
      expect(theme.name, '');
      expect(theme.title.heading, isTrue);
      expect(theme.body.fontSize, 36);
      expect(theme.shapes.fill, const SlideColor.theme(ThemeColor.accent1));
      expect(theme.colors, SlideThemes.light.colors);
    });

    test('fields a newer writer added survive at every level', () {
      final json = {
        ...SlideThemes.light.toJson(),
        'gradients': [1, 2],
        'colors': {
          ...SlideThemes.light.colors.toJson(),
          'accent7': '#ABCDEF',
        },
        'title': {...SlideThemes.light.title.toJson(), 'letterSpacing': 2},
        'shapes': {...SlideThemes.light.shapes.toJson(), 'shadow': true},
      };
      expect(SlideTheme.fromJson(json, r'$').toJson(), json);
    });

    test('a mistyped palette color names its path', () {
      expect(
        () => ThemePalette.fromJson({'text': 'blue'}, r'$.theme.colors'),
        throwsA(
          isA<QslideFormatException>()
              .having((e) => e.path, 'path', r'$.theme.colors.text'),
        ),
      );
    });
  });
}
