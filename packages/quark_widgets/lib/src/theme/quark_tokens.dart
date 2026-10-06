import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../layout/quark_chrome.dart';

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
/// [QuarkTokens.dark] and [QuarkTokens.light] are the two sets the app ships,
/// and what the `classic` theme color yields. Every other theme color derives
/// a set of its own; see `QuarkThemeColor.tokensFor`.
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
    required this.chrome,
    required this.chromeBorder,
    required this.chromeForeground,
    required this.chromeSecondaryForeground,
    required this.chromeMutedForeground,
    required this.chromePrimary,
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

  /// The recessed content surface: side panels, list headers, and strips.
  ///
  /// The app bar and the drawer were drawn in it too, and still match it in
  /// the shipped sets, but they read [chrome] now.
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
  ///
  /// Nobody picks it. A `QuarkThemeColor` derives it from the picked hue so
  /// that it stands out from the content surfaces and from [chrome] alike.
  final Color primary;

  /// Text and icons drawn on top of [primary].
  final Color primaryForeground;

  /// The surface of the chrome: the app bar and the navigation drawer.
  ///
  /// The shipped sets give it the same color as [sidebar]. A derived theme
  /// color makes it clearly colored, which is why text on it has tokens of
  /// its own; [onChrome] swaps them in for a widget that sits on it.
  final Color chrome;

  /// Hairlines on [chrome]: the bar's edge, and the outline of a bar button.
  final Color chromeBorder;

  /// Primary text on [chrome], such as the page name beside the brand badge.
  final Color chromeForeground;

  /// Secondary text and icons on [chrome]: bar buttons and their labels.
  final Color chromeSecondaryForeground;

  /// De-emphasized text on [chrome]: hints and disabled bar buttons.
  final Color chromeMutedForeground;

  /// The accent as drawn on [chrome]: the brand badge, a selected chip, the
  /// active drawer row. [primaryForeground] is legible on it too.
  ///
  /// The shipped sets give it the color of [primary]. On same-hue chrome a
  /// derived theme pushes it further than [primary] has to go.
  final Color chromePrimary;

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
  /// offers them. The first is every event's default: a blue of its own, which
  /// does not follow the theme color. An event stores its index, so reordering
  /// these recolors saved events.
  final List<Color> eventColors;

  /// The dark token set, and Quark's default appearance.
  static const QuarkTokens dark = QuarkTokens(
    background: Color(0xFF070D19),
    card: Color(0xFF0F172A),
    sidebar: Color(0xFF0C1220),
    border: Color(0xFF1E293B),
    input: Color(0xFF131C2E),
    mutedForeground: Color(0xFF7587A1),
    secondaryForeground: Color(0xFF94A3B8),
    foreground: Color(0xFFE2E8F0),
    cardForeground: Color(0xFFE2E8F0),
    primary: Color(0xFF72A7C0),
    primaryForeground: Color(0xFF0F172A),
    chrome: Color(0xFF0C1220),
    chromeBorder: Color(0xFF1E293B),
    chromeForeground: Color(0xFFE2E8F0),
    chromeSecondaryForeground: Color(0xFF94A3B8),
    chromeMutedForeground: Color(0xFF7587A1),
    chromePrimary: Color(0xFF72A7C0),
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
    mutedForeground: Color(0xFF606F85),
    secondaryForeground: Color(0xFF475569),
    foreground: Color(0xFF0F172A),
    cardForeground: Color(0xFF0F172A),
    primary: Color(0xFF3A6B82),
    primaryForeground: Color(0xFFFFFFFF),
    chrome: Color(0xFFF1F5F9),
    chromeBorder: Color(0xFFE2E8F0),
    chromeForeground: Color(0xFF0F172A),
    chromeSecondaryForeground: Color(0xFF475569),
    chromeMutedForeground: Color(0xFF606F85),
    chromePrimary: Color(0xFF3A6B82),
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
  ///
  /// Under a [QuarkChrome] the result is [onChrome], so a widget placed in the
  /// app bar or the drawer reads chrome colors without knowing where it is.
  static QuarkTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<QuarkTokens>() ?? dark;
    return QuarkChrome.isOn(context) ? tokens.onChrome : tokens;
  }

  /// These tokens as a widget sitting on [chrome] should read them: text,
  /// hairlines and the accent swapped for their chrome counterparts,
  /// everything else as it is.
  ///
  /// The surfaces stay, [input] included: a bar button keeps the content's
  /// input fill, and chrome text is legible on it as well. For the shipped
  /// sets this is the same set, so the classic look does not move.
  QuarkTokens get onChrome => copyWith(
    border: chromeBorder,
    foreground: chromeForeground,
    cardForeground: chromeForeground,
    secondaryForeground: chromeSecondaryForeground,
    mutedForeground: chromeMutedForeground,
    primary: chromePrimary,
  );

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
    Color? chrome,
    Color? chromeBorder,
    Color? chromeForeground,
    Color? chromeSecondaryForeground,
    Color? chromeMutedForeground,
    Color? chromePrimary,
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
      chrome: chrome ?? this.chrome,
      chromeBorder: chromeBorder ?? this.chromeBorder,
      chromeForeground: chromeForeground ?? this.chromeForeground,
      chromeSecondaryForeground:
          chromeSecondaryForeground ?? this.chromeSecondaryForeground,
      chromeMutedForeground:
          chromeMutedForeground ?? this.chromeMutedForeground,
      chromePrimary: chromePrimary ?? this.chromePrimary,
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
      chrome: Color.lerp(chrome, other.chrome, t)!,
      chromeBorder: Color.lerp(chromeBorder, other.chromeBorder, t)!,
      chromeForeground: Color.lerp(
        chromeForeground,
        other.chromeForeground,
        t,
      )!,
      chromeSecondaryForeground: Color.lerp(
        chromeSecondaryForeground,
        other.chromeSecondaryForeground,
        t,
      )!,
      chromeMutedForeground: Color.lerp(
        chromeMutedForeground,
        other.chromeMutedForeground,
        t,
      )!,
      chromePrimary: Color.lerp(chromePrimary, other.chromePrimary, t)!,
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
        other.chrome == chrome &&
        other.chromeBorder == chromeBorder &&
        other.chromeForeground == chromeForeground &&
        other.chromeSecondaryForeground == chromeSecondaryForeground &&
        other.chromeMutedForeground == chromeMutedForeground &&
        other.chromePrimary == chromePrimary &&
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
    chrome,
    chromeBorder,
    chromeForeground,
    chromeSecondaryForeground,
    chromeMutedForeground,
    chromePrimary,
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
