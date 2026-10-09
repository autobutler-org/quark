import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/setup/theme_option.dart';
import 'package:quark_icons/quark_icons.dart';

/// Theme selection step — the user picks Light, Dark, or System.
///
/// Selecting an option immediately applies the theme (live preview) and
/// persists the preference via [AppSettings]. The user can proceed with
/// any selection; the default is whatever [AppSettings] loaded on startup
/// (i.e. System on first boot).
///
/// It is the last step, so [footer] is where the setup page puts what else
/// the new owner can do before starting: naming the Quark (#2344).
class ThemeStep extends StatelessWidget {
  final VoidCallback onContinue;

  /// Shown between the theme options and the button — the setup page's
  /// device name field. Nothing when null.
  final Widget? footer;

  const ThemeStep({super.key, required this.onContinue, this.footer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.instance.themeMode,
      builder: (context, currentMode, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              QuarkIcons.palette_outlined,
              size: 56,
              color: theme.colorScheme.primary,
              semanticLabel: 'Theme',
            ),
            const SizedBox(height: 16),
            Text(
              'Choose your theme',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You can change this at any time in Settings.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            ThemeOption(
              icon: QuarkIcons.brightness_auto_rounded,
              label: 'System',
              description: 'Follows your device setting',
              isSelected: currentMode == ThemeMode.system,
              onTap: () => AppSettings.instance.setThemeMode(ThemeMode.system),
            ),
            const SizedBox(height: 12),
            ThemeOption(
              icon: QuarkIcons.light_mode_rounded,
              label: 'Light',
              description: 'Always use light theme',
              isSelected: currentMode == ThemeMode.light,
              onTap: () => AppSettings.instance.setThemeMode(ThemeMode.light),
            ),
            const SizedBox(height: 12),
            ThemeOption(
              icon: QuarkIcons.dark_mode_rounded,
              label: 'Dark',
              description: 'Always use dark theme',
              isSelected: currentMode == ThemeMode.dark,
              onTap: () => AppSettings.instance.setThemeMode(ThemeMode.dark),
            ),

            const SizedBox(height: 32),

            ?footer,

            FilledButton(
              onPressed: onContinue,
              child: const Text('Get started'),
            ),
          ],
        );
      },
    );
  }
}
