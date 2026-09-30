import 'package:flutter/material.dart';

import 'quark_tokens.dart';

/// Builds Quark's [ThemeData] from a [QuarkTokens] set.
///
/// The tokens are attached to the result as a [ThemeExtension], so a widget can
/// reach values the Material [ColorScheme] has no slot for — `sidebar`,
/// `warning`, `success`, the spacing scale — with [QuarkTokens.of].
///
/// ```dart
/// MaterialApp(
///   theme: QuarkTheme.light(),
///   darkTheme: QuarkTheme.dark(),
/// );
/// ```
abstract final class QuarkTheme {
  /// Quark's dark theme, built from [QuarkTokens.dark].
  static ThemeData dark() => from(QuarkTokens.dark, Brightness.dark);

  /// Quark's light theme, built from [QuarkTokens.light].
  static ThemeData light() => from(QuarkTokens.light, Brightness.light);

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
      outline: tokens.outline,
      outlineVariant: tokens.border,
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
      // Every InkWell and ListTile paints this while it holds keyboard focus.
      // Material's default is a faint 12% wash; a keyboard user has to be
      // able to find it at a glance (WCAG 2.4.7).
      focusColor: tokens.primary.withValues(alpha: focusAlpha),
      useMaterial3: true,
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.sidebar,
        foregroundColor: tokens.foreground,
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
        // A field's edge is how a user finds it, so it is the 3:1 outline,
        // not the decorative hairline (#2600).
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.outline),
        ),
        // Two pixels, not one. A keyboard user has no pointer to tell them
        // where they are, and a focused field that differs from a resting one
        // only in hue is invisible to anyone who cannot separate those two
        // colors (#2028).
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.primary, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.error, width: 2),
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
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(side: focusRing(tokens)),
      ),
      dividerTheme: DividerThemeData(color: tokens.border, thickness: 1),
      drawerTheme: DrawerThemeData(backgroundColor: tokens.sidebar),
      listTileTheme: ListTileThemeData(
        textColor: tokens.foreground,
        iconColor: tokens.secondaryForeground,
      ),
      // An on switch is a solid primary track, not a 30% tint of one: the
      // tint fell to 1.4–1.7:1 against the card, below WCAG 1.4.11 (#2600).
      // An off switch shows its track edge in the outline for the same reason.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.primaryForeground;
          }
          return tokens.mutedForeground;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.primary;
          return tokens.input;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.primary;
          return tokens.outline;
        }),
        overlayColor: _focusHalo(tokens),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.primary;
          return Colors.transparent;
        }),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? tokens.primary
                : tokens.outline,
            width: states.contains(WidgetState.focused) ? 2 : 1.5,
          ),
        ),
        overlayColor: _focusHalo(tokens),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
      ),
      radioTheme: RadioThemeData(overlayColor: _focusHalo(tokens)),
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

  /// The outline a button wears while it holds keyboard focus: two pixels of
  /// [QuarkTokens.primary].
  ///
  /// Material's own focus cue for a button is a faint overlay tint, which on a
  /// filled button sits on top of a color it barely differs from. A keyboard
  /// user needs to see where they are before they press Enter — on a sign-in
  /// form most of all, which is where this was reported (#2028).
  ///
  /// [resting] is the border the button wears the rest of the time, or null
  /// for no border at all. A widget that sets its own `side` in a
  /// [ButtonStyle] overrides the theme's, so it passes this instead of a
  /// plain [BorderSide] to keep the ring.
  static WidgetStateProperty<BorderSide?> focusRing(
    QuarkTokens tokens, {
    Color? resting,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: tokens.primary, width: 2);
      }
      return resting == null ? null : BorderSide(color: resting);
    });
  }

  /// The halo a switch, checkbox or radio wears while it holds keyboard
  /// focus. Material's default is a tenth-strength tint, which is next to
  /// invisible on a card; this one is strong enough to find.
  static WidgetStateProperty<Color?> _focusHalo(QuarkTokens tokens) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return tokens.primary.withValues(alpha: focusAlpha);
        }
        return null;
      });

  /// How strong the focus tint on an ink surface or a toggle's halo is.
  static const double focusAlpha = 0.32;
}
