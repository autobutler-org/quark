import 'package:flutter/material.dart';

import 'quark_theme_color.dart';
import 'quark_tokens.dart';

/// Builds Quark's [ThemeData] from a [QuarkTokens] set.
///
/// The tokens are attached to the result as a [ThemeExtension], so a widget can
/// reach values the Material [ColorScheme] has no slot for — `sidebar`,
/// `warning`, `success`, the spacing scale — with [QuarkTokens.of].
///
/// Both constructors take the theme color the whole theme is derived from.
/// It is required, so a caller cannot fall back to classic by leaving it out
/// while the rest of the app wears the picked color (#2786):
///
/// ```dart
/// final themeColor = QuarkThemeColor.parse(settings.themeColor);
/// MaterialApp(
///   theme: QuarkTheme.light(themeColor: themeColor),
///   darkTheme: QuarkTheme.dark(themeColor: themeColor),
/// );
/// ```
abstract final class QuarkTheme {
  /// Quark's dark theme, built from the dark tokens of [themeColor]. That is
  /// [QuarkTokens.dark] for [QuarkThemeColor.classic].
  static ThemeData dark({required QuarkThemeColor themeColor}) =>
      from(themeColor.tokensFor(Brightness.dark), Brightness.dark);

  /// Quark's light theme, built from the light tokens of [themeColor]. That
  /// is [QuarkTokens.light] for [QuarkThemeColor.classic].
  static ThemeData light({required QuarkThemeColor themeColor}) =>
      from(themeColor.tokensFor(Brightness.light), Brightness.light);

  /// Quark's high-contrast dark theme, built from
  /// [QuarkTokens.highContrastDark]. It takes no theme color: a tinted surface
  /// would cost the contrast it exists for.
  static ThemeData highContrastDark() =>
      from(QuarkTokens.highContrastDark, Brightness.dark);

  /// Quark's high-contrast light theme, built from
  /// [QuarkTokens.highContrastLight].
  static ThemeData highContrastLight() =>
      from(QuarkTokens.highContrastLight, Brightness.light);

  /// Builds a [ThemeData] for [brightness] out of [tokens].
  ///
  /// Every color, radius, and border in the returned theme comes from [tokens],
  /// which is what lets the widget gallery's theme panel restyle the whole app
  /// from edited values.
  static ThemeData from(QuarkTokens tokens, Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: tokens.primary,
      brightness: brightness,
      surface: tokens.card,
      onSurface: tokens.foreground,
      primary: tokens.primary,
      onPrimary: tokens.primaryForeground,
      secondary: tokens.sidebar,
      onSecondary: tokens.secondaryForeground,
      error: tokens.error,
      onError: tokens.errorForeground,
      outline: tokens.border,
      outlineVariant: tokens.border,
      // Left to `fromSeed`, the containers are Material tones of the accent
      // that match no Quark surface, and a bar filled with one drifts from
      // the chrome beside it (#2786). They run from the page to a well:
      // `surfaceContainer` is what Material fills a navigation bar with, so
      // it is the chrome, and the highest is the card under a faint wash of
      // the text color, for filled fields and header cells.
      surfaceContainerLowest: tokens.background,
      surfaceContainerLow: tokens.sidebar,
      surfaceContainer: tokens.chrome,
      surfaceContainerHigh: tokens.card,
      surfaceContainerHighest: Color.alphaBlend(
        tokens.foreground.withValues(alpha: 0.08),
        tokens.card,
      ),
    );

    // The recessive track behind an off switch: the input fill reads as a well
    // on dark, but disappears on light, where the hairline is the right weight.
    final switchTrackOff = brightness == Brightness.dark
        ? tokens.input
        : tokens.border;

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
      useMaterial3: true,
      // Material's desktop defaults (shrinkWrap targets, compact density) bring
      // a stock button down to 32px. A touchscreen laptop, a Chromebook or a
      // tablet asking for the desktop site all report a desktop platform, so
      // every platform keeps the 48dp touch target (#2605, #2939).
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.chrome,
        foregroundColor: tokens.chromeForeground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Bar buttons are bordered, so they need a gap from the screen edge
        // that a bare icon's own padding used to provide.
        actionsPadding: EdgeInsets.only(right: tokens.spacingSm),
      ),
      cardTheme: CardThemeData(
        color: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          side: BorderSide(color: tokens.border),
        ),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.border),
        ),
        // [QuarkTokens.focusRingWidth], two pixels or more, not one. A keyboard user has no pointer to tell them
        // where they are, and a focused field that differs from a resting one
        // only in hue is invisible to anyone who cannot separate those two
        // colors (#2028).
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(
            color: tokens.primary,
            width: tokens.focusRingWidth,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(
            color: tokens.error,
            width: tokens.focusRingWidth,
          ),
        ),
        labelStyle: TextStyle(color: tokens.secondaryForeground),
        hintStyle: TextStyle(color: tokens.mutedForeground),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.primaryForeground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
        ).copyWith(side: focusRing(tokens)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.secondaryForeground,
          side: BorderSide(color: tokens.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
        ).copyWith(side: focusRing(tokens, resting: tokens.border)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.primary,
        ).copyWith(side: focusRing(tokens)),
      ),
      // Material's only focus cue for an icon button is a faint tint, and a
      // bare glyph has no edge for a tint to show against (#2604).
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(side: focusRing(tokens)),
      ),
      dividerTheme: DividerThemeData(color: tokens.border, thickness: 1),
      drawerTheme: DrawerThemeData(backgroundColor: tokens.chrome),
      listTileTheme: ListTileThemeData(
        textColor: tokens.foreground,
        iconColor: tokens.secondaryForeground,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.primary;
          return tokens.mutedForeground;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.primary.withValues(alpha: 0.3);
          }
          return switchTrackOff;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.primary;
          return Colors.transparent;
        }),
        side: BorderSide(color: tokens.border, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.card,
        contentTextStyle: TextStyle(color: tokens.foreground),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          side: BorderSide(color: tokens.border),
        ),
      ),
      iconTheme: IconThemeData(color: tokens.secondaryForeground, size: 20),
    );
  }

  /// The outline a button wears while it holds keyboard focus:
  /// [QuarkTokens.focusRingWidth] pixels of [QuarkTokens.primary].
  ///
  /// Material's own focus cue for a button is a faint overlay tint, which on a
  /// filled button sits on top of a color it barely differs from. A keyboard
  /// user needs to see where they are before they press Enter — on a sign-in
  /// form most of all, which is where this was reported (#2028).
  ///
  /// [resting] is the border the button wears the rest of the time, or null
  /// for no border at all. A button that sets its own `side` replaces the
  /// theme's, so it passes its border through here to keep the outline
  /// (#2604).
  static WidgetStateProperty<BorderSide?> focusRing(
    QuarkTokens tokens, {
    Color? resting,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: tokens.primary, width: tokens.focusRingWidth);
      }
      return resting == null ? null : BorderSide(color: resting);
    });
  }
}
