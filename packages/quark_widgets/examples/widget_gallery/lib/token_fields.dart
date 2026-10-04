import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One editable color on [QuarkTokens]: how to read it and how to replace it.
///
/// The theme panel builds a hex field from each of these and the "Theme tokens"
/// gallery entry builds a swatch from each, so the two cannot drift apart.
typedef ColorField = ({
  String name,
  Color Function(QuarkTokens tokens) read,
  QuarkTokens Function(QuarkTokens tokens, Color value) write,
});

/// One editable number on [QuarkTokens] — a radius or a step on the spacing
/// scale — with the slider range that suits it.
typedef NumberField = ({
  String name,
  double max,
  double Function(QuarkTokens tokens) read,
  QuarkTokens Function(QuarkTokens tokens, double value) write,
});

/// Every color token, in the order the theme panel shows them.
final List<ColorField> colorFields = [
  (
    name: 'background',
    read: (t) => t.background,
    write: (t, v) => t.copyWith(background: v),
  ),
  (name: 'card', read: (t) => t.card, write: (t, v) => t.copyWith(card: v)),
  (
    name: 'sidebar',
    read: (t) => t.sidebar,
    write: (t, v) => t.copyWith(sidebar: v),
  ),
  (
    name: 'border',
    read: (t) => t.border,
    write: (t, v) => t.copyWith(border: v),
  ),
  (name: 'input', read: (t) => t.input, write: (t, v) => t.copyWith(input: v)),
  (
    name: 'mutedForeground',
    read: (t) => t.mutedForeground,
    write: (t, v) => t.copyWith(mutedForeground: v),
  ),
  (
    name: 'secondaryForeground',
    read: (t) => t.secondaryForeground,
    write: (t, v) => t.copyWith(secondaryForeground: v),
  ),
  (
    name: 'foreground',
    read: (t) => t.foreground,
    write: (t, v) => t.copyWith(foreground: v),
  ),
  (
    name: 'cardForeground',
    read: (t) => t.cardForeground,
    write: (t, v) => t.copyWith(cardForeground: v),
  ),
  (
    name: 'primary',
    read: (t) => t.primary,
    write: (t, v) => t.copyWith(primary: v),
  ),
  (
    name: 'primaryForeground',
    read: (t) => t.primaryForeground,
    write: (t, v) => t.copyWith(primaryForeground: v),
  ),
  (
    name: 'chrome',
    read: (t) => t.chrome,
    write: (t, v) => t.copyWith(chrome: v),
  ),
  (
    name: 'chromeBorder',
    read: (t) => t.chromeBorder,
    write: (t, v) => t.copyWith(chromeBorder: v),
  ),
  (
    name: 'chromeForeground',
    read: (t) => t.chromeForeground,
    write: (t, v) => t.copyWith(chromeForeground: v),
  ),
  (
    name: 'chromeSecondaryForeground',
    read: (t) => t.chromeSecondaryForeground,
    write: (t, v) => t.copyWith(chromeSecondaryForeground: v),
  ),
  (
    name: 'chromeMutedForeground',
    read: (t) => t.chromeMutedForeground,
    write: (t, v) => t.copyWith(chromeMutedForeground: v),
  ),
  (
    name: 'chromePrimary',
    read: (t) => t.chromePrimary,
    write: (t, v) => t.copyWith(chromePrimary: v),
  ),
  (name: 'error', read: (t) => t.error, write: (t, v) => t.copyWith(error: v)),
  (
    name: 'errorForeground',
    read: (t) => t.errorForeground,
    write: (t, v) => t.copyWith(errorForeground: v),
  ),
  (
    name: 'warning',
    read: (t) => t.warning,
    write: (t, v) => t.copyWith(warning: v),
  ),
  (
    name: 'success',
    read: (t) => t.success,
    write: (t, v) => t.copyWith(success: v),
  ),
  for (var i = 0; i < QuarkTokens.dark.eventColors.length; i++)
    (
      name: 'eventColors[$i]',
      read: (t) => t.eventColors[i],
      write: (t, v) => t.copyWith(eventColors: [...t.eventColors]..[i] = v),
    ),
];

/// Every radius and spacing token, in the order the theme panel shows them.
final List<NumberField> numberFields = [
  (
    name: 'radiusSm',
    max: 32,
    read: (t) => t.radiusSm,
    write: (t, v) => t.copyWith(radiusSm: v),
  ),
  (
    name: 'radiusMd',
    max: 32,
    read: (t) => t.radiusMd,
    write: (t, v) => t.copyWith(radiusMd: v),
  ),
  (
    name: 'radiusLg',
    max: 32,
    read: (t) => t.radiusLg,
    write: (t, v) => t.copyWith(radiusLg: v),
  ),
  (
    name: 'spacingXs',
    max: 48,
    read: (t) => t.spacingXs,
    write: (t, v) => t.copyWith(spacingXs: v),
  ),
  (
    name: 'spacingSm',
    max: 48,
    read: (t) => t.spacingSm,
    write: (t, v) => t.copyWith(spacingSm: v),
  ),
  (
    name: 'spacingMd',
    max: 48,
    read: (t) => t.spacingMd,
    write: (t, v) => t.copyWith(spacingMd: v),
  ),
  (
    name: 'spacingLg',
    max: 48,
    read: (t) => t.spacingLg,
    write: (t, v) => t.copyWith(spacingLg: v),
  ),
  (
    name: 'spacingXl',
    max: 48,
    read: (t) => t.spacingXl,
    write: (t, v) => t.copyWith(spacingXl: v),
  ),
];

/// Formats [color] the way the hex fields hand it back: `#RRGGBB`.
String toHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Parses `#RRGGBB`, `RRGGBB`, or `#AARRGGBB`.
///
/// Returns null when [text] is not a color, so a half-typed field can keep the
/// value it had instead of blanking the theme.
Color? parseHex(String text) {
  final digits = text.trim().replaceFirst('#', '');
  if (digits.length != 6 && digits.length != 8) return null;
  final value = int.tryParse(digits, radix: 16);
  if (value == null) return null;
  return Color(digits.length == 6 ? 0xFF000000 | value : value);
}
