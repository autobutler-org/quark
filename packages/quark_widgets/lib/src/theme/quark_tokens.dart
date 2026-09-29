import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// The design tokens every Quark widget draws from: colors, corner radii, and
/// a spacing scale.
///
/// Tokens are values, not constants, so they can be edited at runtime — the
/// widget gallery's theme panel rebuilds the whole app from an edited
/// [QuarkTokens]. A widget that hardcodes a color instead of reading a token
/// stops following the panel, which is how you spot it.
///
/// Reach them through the theme:
///
/// ```dart
/// final tokens = QuarkTokens.of(context);
/// Container(
///   color: tokens.card,
///   padding: EdgeInsets.all(tokens.spacingMd),
/// );
/// ```
///
/// [QuarkTokens.dark] and [QuarkTokens.light] are the two sets the app ships.
@immutable
class QuarkTokens extends ThemeExtension<QuarkTokens> {
  /// Creates a token set. Every value is required so a new token cannot be
  /// silently defaulted into a theme that has not been designed for it.
  const QuarkTokens({
    required this.background,
    required this.card,
    required this.sidebar,
    required this.border,
    required this.input,
    required this.mutedForeground,
    required this.secondaryForeground,
    required this.foreground,
    required this.cardForeground,
    required this.primary,
    required this.primaryForeground,
    required this.error,
    required this.errorForeground,
    required this.warning,
    required this.success,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.spacingXs,
    required this.spacingSm,
    required this.spacingMd,
    required this.spacingLg,
    required this.spacingXl,
    required this.eventColors,
  });

  /// The page behind every surface, used as the scaffold background.
  final Color background;

  /// The surface color for cards, dialogs, menus, and snack bars.
  final Color card;

  /// The surface color for the app bar, the drawer, and side panels.
  final Color sidebar;

  /// Hairlines: outlines, dividers, and unfocused input borders.
  final Color border;

  /// The fill behind text fields and other editable inputs.
  final Color input;

  /// De-emphasized text: hints, placeholders, and disabled labels.
  final Color mutedForeground;

  /// Secondary text and icons — labels, captions, and icon buttons.
  final Color secondaryForeground;

  /// Primary body text on [background].
  final Color foreground;

  /// Primary body text on [card].
  final Color cardForeground;

  /// The accent color: filled buttons, focus rings, selection, and links.
  final Color primary;

  /// Text and icons drawn on top of [primary].
  final Color primaryForeground;

  /// The error accent for destructive actions and failure states.
  final Color error;

  /// Text and icons drawn on top of [error].
  ///
  /// This sits on the error fill, so it has to contrast with [error] rather
  /// than tint toward it: a lighter shade of the same red reads as a disabled
  /// label on a destructive button (#1789).
  final Color errorForeground;

  /// The warning accent for non-blocking problems.
  final Color warning;

  /// The success accent for completed actions.
  final Color success;

  /// The tight corner radius, for checkboxes and other small controls.
  final double radiusSm;

  /// The default corner radius, for buttons, inputs, and menus.
  final double radiusMd;

  /// The generous corner radius, for cards and dialogs.
  final double radiusLg;

  /// The tightest gap in the spacing scale.
  final double spacingXs;

  /// A small gap: between an icon and its label, or between chips.
  final double spacingSm;

  /// The default gap: padding inside a card, between form rows.
  final double spacingMd;

  /// A large gap: between sections of a page.
  final double spacingLg;

  /// The widest gap in the spacing scale, for page-level margins.
  final double spacingXl;

  /// The colors a person can give a calendar event, in the order the picker
  /// offers them. The first is [primary], every event's default. An event
  /// stores its index, so reordering these recolors saved events.
  final List<Color> eventColors;

  /// The dark token set, and Quark's default appearance.
  static const QuarkTokens dark = QuarkTokens(
    background: Color(0xFF070D19),
    card: Color(0xFF0F172A),
    sidebar: Color(0xFF0C1220),
    border: Color(0xFF1E293B),
    input: Color(0xFF131C2E),
    mutedForeground: Color(0xFF475569),
    secondaryForeground: Color(0xFF94A3B8),
    foreground: Color(0xFFE2E8F0),
    cardForeground: Color(0xFFE2E8F0),
    primary: Color(0xFF0EA5E9),
    primaryForeground: Color(0xFFFFFFFF),
    error: Color(0xFFEF4444),
    errorForeground: Color(0xFFFFFFFF),
    warning: Color(0xFFF59E0B),
    success: Color(0xFF10B981),
    radiusSm: 4,
    radiusMd: 8,
    radiusLg: 12,
    spacingXs: 4,
    spacingSm: 8,
    spacingMd: 16,
    spacingLg: 24,
    spacingXl: 32,
    eventColors: [
      Color(0xFF0EA5E9), // sky
      Color(0xFF10B981), // green
      Color(0xFFF59E0B), // amber
      Color(0xFF8B5CF6), // violet
      Color(0xFFF43F5E), // rose
      Color(0xFF94A3B8), // slate
    ],
  );

  /// The light token set.
  static const QuarkTokens light = QuarkTokens(
    background: Color(0xFFF8FAFC),
    card: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    input: Color(0xFFFFFFFF),
    mutedForeground: Color(0xFF64748B),
    secondaryForeground: Color(0xFF475569),
    foreground: Color(0xFF0F172A),
    cardForeground: Color(0xFF0F172A),
    primary: Color(0xFF0EA5E9),
    primaryForeground: Color(0xFFFFFFFF),
    error: Color(0xFFDC2626),
    errorForeground: Color(0xFFFFFFFF),
    warning: Color(0xFFF59E0B),
    success: Color(0xFF10B981),
    radiusSm: 4,
    radiusMd: 8,
    radiusLg: 12,
    spacingXs: 4,
    spacingSm: 8,
    spacingMd: 16,
    spacingLg: 24,
    spacingXl: 32,
    eventColors: [
      Color(0xFF0EA5E9), // sky
      Color(0xFF059669), // green
      Color(0xFFD97706), // amber
      Color(0xFF7C3AED), // violet
      Color(0xFFE11D48), // rose
      Color(0xFF64748B), // slate
    ],
  );

  /// The tokens attached to the nearest [Theme], falling back to [dark] when a
  /// widget is rendered under a bare [ThemeData] (a test, or a host app that
  /// has not adopted [QuarkTheme]).
  static QuarkTokens of(BuildContext context) =>
      Theme.of(context).extension<QuarkTokens>() ?? dark;

  @override
  QuarkTokens copyWith({
    Color? background,
    Color? card,
    Color? sidebar,
    Color? border,
    Color? input,
    Color? mutedForeground,
    Color? secondaryForeground,
    Color? foreground,
    Color? cardForeground,
    Color? primary,
    Color? primaryForeground,
    Color? error,
    Color? errorForeground,
    Color? warning,
    Color? success,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? spacingXs,
    double? spacingSm,
    double? spacingMd,
    double? spacingLg,
    double? spacingXl,
    List<Color>? eventColors,
  }) {
    return QuarkTokens(
      background: background ?? this.background,
      card: card ?? this.card,
      sidebar: sidebar ?? this.sidebar,
      border: border ?? this.border,
      input: input ?? this.input,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      secondaryForeground: secondaryForeground ?? this.secondaryForeground,
      foreground: foreground ?? this.foreground,
      cardForeground: cardForeground ?? this.cardForeground,
      primary: primary ?? this.primary,
      primaryForeground: primaryForeground ?? this.primaryForeground,
      error: error ?? this.error,
      errorForeground: errorForeground ?? this.errorForeground,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      spacingXs: spacingXs ?? this.spacingXs,
      spacingSm: spacingSm ?? this.spacingSm,
      spacingMd: spacingMd ?? this.spacingMd,
      spacingLg: spacingLg ?? this.spacingLg,
      spacingXl: spacingXl ?? this.spacingXl,
      eventColors: eventColors ?? this.eventColors,
    );
  }

  @override
  QuarkTokens lerp(covariant QuarkTokens? other, double t) {
    if (other == null) return this;
    return QuarkTokens(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      border: Color.lerp(border, other.border, t)!,
      input: Color.lerp(input, other.input, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      secondaryForeground: Color.lerp(
        secondaryForeground,
        other.secondaryForeground,
        t,
      )!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      cardForeground: Color.lerp(cardForeground, other.cardForeground, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryForeground: Color.lerp(
        primaryForeground,
        other.primaryForeground,
        t,
      )!,
      error: Color.lerp(error, other.error, t)!,
      errorForeground: Color.lerp(errorForeground, other.errorForeground, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t)!,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t)!,
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t)!,
      spacingXs: lerpDouble(spacingXs, other.spacingXs, t)!,
      spacingSm: lerpDouble(spacingSm, other.spacingSm, t)!,
      spacingMd: lerpDouble(spacingMd, other.spacingMd, t)!,
      spacingLg: lerpDouble(spacingLg, other.spacingLg, t)!,
      spacingXl: lerpDouble(spacingXl, other.spacingXl, t)!,
      // Pairs up by index; a set longer than the other keeps its extras as
      // they are rather than fading them to nothing.
      eventColors: [
        for (var i = 0; i < eventColors.length; i++)
          i < other.eventColors.length
              ? Color.lerp(eventColors[i], other.eventColors[i], t)!
              : eventColors[i],
      ],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QuarkTokens &&
        other.background == background &&
        other.card == card &&
        other.sidebar == sidebar &&
        other.border == border &&
        other.input == input &&
        other.mutedForeground == mutedForeground &&
        other.secondaryForeground == secondaryForeground &&
        other.foreground == foreground &&
        other.cardForeground == cardForeground &&
        other.primary == primary &&
        other.primaryForeground == primaryForeground &&
        other.error == error &&
        other.errorForeground == errorForeground &&
        other.warning == warning &&
        other.success == success &&
        other.radiusSm == radiusSm &&
        other.radiusMd == radiusMd &&
        other.radiusLg == radiusLg &&
        other.spacingXs == spacingXs &&
        other.spacingSm == spacingSm &&
        other.spacingMd == spacingMd &&
        other.spacingLg == spacingLg &&
        other.spacingXl == spacingXl &&
        listEquals(other.eventColors, eventColors);
  }

  @override
  int get hashCode => Object.hashAll([
    background,
    card,
    sidebar,
    border,
    input,
    mutedForeground,
    secondaryForeground,
    foreground,
    cardForeground,
    primary,
    primaryForeground,
    error,
    errorForeground,
    warning,
    success,
    radiusSm,
    radiusMd,
    radiusLg,
    spacingXs,
    spacingSm,
    spacingMd,
    spacingLg,
    spacingXl,
    Object.hashAll(eventColors),
  ]);
}
