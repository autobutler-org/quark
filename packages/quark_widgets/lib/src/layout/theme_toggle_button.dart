import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import 'quark_bar_icon_button.dart';

/// A [QuarkBarIconButton] that switches the app between light and dark.
///
/// The current [mode] comes in and the chosen one goes out; the package never
/// reads or writes the app's settings. From [ThemeMode.system] the button
/// commits to light, because the first tap is a user saying they want the
/// other one, not the one they are already looking at.
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
  /// Creates a toggle showing the alternative to [mode].
  const ThemeToggleButton({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  /// The theme mode currently in effect, which decides the glyph and tooltip.
  final ThemeMode mode;

  /// Called with the mode the user asked for. Never called with [mode].
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final (icon, tooltip, nextMode) = switch (mode) {
      ThemeMode.light => (
        QuarkIcons.dark_mode_rounded,
        'Switch to dark mode',
        ThemeMode.dark,
      ),
      ThemeMode.dark => (
        QuarkIcons.light_mode_rounded,
        'Switch to light mode',
        ThemeMode.light,
      ),
      ThemeMode.system => (
        QuarkIcons.brightness_auto_rounded,
        'Switch to light mode',
        ThemeMode.light,
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
