import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import 'quark_bar_icon_button.dart';

/// A [QuarkBarIconButton] that steps the app through its three theme modes.
///
/// The app's one theme control (#2053). Each tap moves to the next mode in
/// turn: matching the device, then light, then dark, then back. The glyph shows
/// the mode in effect and the tooltip names it and the one a tap moves to. The
/// current [mode] comes in and the chosen one goes out; the package never
/// reads or writes the app's settings.
///
/// Key prefixes: `theme_toggle` on the control itself.
///
/// ```dart
/// ThemeToggleButton(
///   mode: settings.themeMode.value,
///   onChanged: settings.setThemeMode,
/// );
/// ```
class ThemeToggleButton extends StatelessWidget {
  /// Creates a toggle showing [mode] and offering the one after it.
  const ThemeToggleButton({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  /// The theme mode currently in effect, which decides the glyph and tooltip.
  final ThemeMode mode;

  /// Called with the mode after [mode]. Never called with [mode].
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final (icon, tooltip, nextMode) = switch (mode) {
      ThemeMode.system => (
        QuarkIcons.brightness_auto_rounded,
        'Theme matches your device. Switch to light',
        ThemeMode.light,
      ),
      ThemeMode.light => (
        QuarkIcons.light_mode_rounded,
        'Theme is light. Switch to dark',
        ThemeMode.dark,
      ),
      ThemeMode.dark => (
        QuarkIcons.dark_mode_rounded,
        'Theme is dark. Switch to match your device',
        ThemeMode.system,
      ),
    };

    return QuarkBarIconButton(
      key: const ValueKey('theme_toggle'),
      icon: icon,
      tooltip: tooltip,
      onPressed: () => onChanged(nextMode),
    );
  }
}
