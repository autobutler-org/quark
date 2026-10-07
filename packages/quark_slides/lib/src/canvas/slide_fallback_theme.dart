import 'package:flutter/material.dart';

import '../theme/slide_theme.dart';
import '../theme/slide_themes.dart';
import '../theme/theme_color.dart';
import 'slide_canvas_style.dart';

/// The theme `SlideCanvas` draws a presentation in when it has none: the
/// host's colors on [SlideThemes.light]'s type.
///
/// The background and text are [style]'s [SlideCanvasStyle.slideColor] and
/// [SlideCanvasStyle.textColor], body text is [SlideCanvasStyle.fontSize],
/// and the first four accents are [scheme]'s primary, secondary, tertiary
/// and error colors — so a deck without a theme looks like the app around
/// it. The other roles keep the light theme's colors.
///
/// ```dart
/// final theme = deck.theme ??
///     slideFallbackTheme(
///       SlideCanvasStyle.fromTheme(Theme.of(context)),
///       Theme.of(context).colorScheme,
///     );
/// ```
SlideTheme slideFallbackTheme(SlideCanvasStyle style, ColorScheme scheme) {
  final light = SlideThemes.light;
  return light.copyWith(
    id: '',
    name: '',
    colors: light.colors.copyWith({
      ThemeColor.background: style.slideColor.toARGB32(),
      ThemeColor.text: style.textColor.toARGB32(),
      ThemeColor.accent1: scheme.primary.toARGB32(),
      ThemeColor.accent2: scheme.secondary.toARGB32(),
      ThemeColor.accent3: scheme.tertiary.toARGB32(),
      ThemeColor.accent4: scheme.error.toARGB32(),
    }),
    body: light.body.copyWith(fontSize: style.fontSize),
  );
}
