import 'package:flutter/material.dart';
import 'package:quark/widgets/host_manager.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The General tab of Settings (#2350): backend hosts, theme, the theme color
/// color (#2740), the auto-refresh interval and demo mode, plus a link to the
/// drives. Beta switches live on the Features tab (#2542).
///
/// First because it holds the backend hosts, which every "manage hosts" link
/// in the app lands on. The page owns the values; this tab renders them and
/// reports changes.
class SettingsGeneralTab extends StatelessWidget {
  /// Creates the tab.
  const SettingsGeneralTab({
    required this.theme,
    required this.onThemeChanged,
    required this.themeColor,
    required this.followsQuarkThemeColor,
    required this.quarkThemeColor,
    this.onThemeColorChanged,
    this.onQuarkThemeColorChanged,
    required this.refreshIntervalSeconds,
    required this.onRefreshIntervalChanged,
    required this.demoMode,
    required this.onDemoModeChanged,
    required this.onHostsChanged,
    this.onOpenStorage,
    this.header,
    super.key,
  });

  /// The selected theme.
  final ThemeMode theme;

  /// Called with the theme the user picked.
  final ValueChanged<ThemeMode> onThemeChanged;

  /// The theme color the app wears: the user's own, or the Quark's while
  /// [followsQuarkThemeColor].
  final QuarkThemeColor themeColor;

  /// Whether the user follows the Quark's default theme color rather than one of
  /// their own.
  final bool followsQuarkThemeColor;

  /// The Quark's default theme color, which an admin sets.
  final QuarkThemeColor quarkThemeColor;

  /// Called with the storage string of the theme color the user picked for
  /// themselves, empty to follow the Quark's. Null hides the section, as
  /// when nobody is signed in.
  final ValueChanged<String>? onThemeColorChanged;

  /// Called with the storage string of the theme color an admin picked as the
  /// Quark's default. Null hides the section, as it is for a non-admin.
  final ValueChanged<String>? onQuarkThemeColorChanged;

  /// How often pages refresh themselves, in seconds; 0 is off.
  final int refreshIntervalSeconds;

  /// Called with the interval the user picked, in seconds.
  final ValueChanged<int> onRefreshIntervalChanged;

  /// Whether demo mode is on.
  final bool demoMode;

  /// Called when the user flips demo mode.
  final ValueChanged<bool> onDemoModeChanged;

  /// Called after a host is added, removed or switched.
  final VoidCallback onHostsChanged;

  /// Opens the drives page. Null hides the link, as when no Quark is set.
  final VoidCallback? onOpenStorage;

  /// Shown above the tab's content and scrolled with it, such as the
  /// page's disconnected banner; null shows nothing.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final onThemeColorChanged = this.onThemeColorChanged;
    final onQuarkThemeColorChanged = this.onQuarkThemeColorChanged;
    const heading = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (header != null) ...[header!, const SizedBox(height: 24)],
        const Text('Backend hosts', style: heading),
        const SizedBox(height: 8),
        HostManager(onChanged: onHostsChanged),
        const SizedBox(height: 24),
        const Text('Theme', style: heading),
        RadioGroup<ThemeMode>(
          groupValue: theme,
          onChanged: (v) {
            if (v != null) onThemeChanged(v);
          },
          child: const Column(
            children: [
              RadioListTile<ThemeMode>(
                title: Text('System'),
                value: ThemeMode.system,
              ),
              RadioListTile<ThemeMode>(
                title: Text('Light'),
                value: ThemeMode.light,
              ),
              RadioListTile<ThemeMode>(
                title: Text('Dark'),
                value: ThemeMode.dark,
              ),
            ],
          ),
        ),
        if (onThemeColorChanged != null) ...[
          const SizedBox(height: 24),
          const Text('Theme color', style: heading),
          const SizedBox(height: 8),
          QuarkThemeColorPicker(
            key: const ValueKey('settings_theme_color'),
            value: themeColor,
            usingDefault: followsQuarkThemeColor,
            onChanged: (picked) => onThemeColorChanged(picked.storageValue),
            onUseDefault: () => onThemeColorChanged(''),
          ),
        ],
        if (onQuarkThemeColorChanged != null) ...[
          const SizedBox(height: 24),
          const Text("This Quark's default", style: heading),
          const SizedBox(height: 4),
          const Text(
            'The theme color for everyone who has not picked their own.',
          ),
          const SizedBox(height: 8),
          QuarkThemeColorPicker(
            key: const ValueKey('settings_quark_theme_color'),
            value: quarkThemeColor,
            onChanged: (picked) =>
                onQuarkThemeColorChanged(picked.storageValue),
          ),
        ],
        const SizedBox(height: 24),
        const Text('Auto-refresh interval', style: heading),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: refreshIntervalSeconds,
          // Full width and as tall as its text, so the choice still fits at
          // large text sizes (#2606).
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Disabled')),
            DropdownMenuItem(value: 10, child: Text('10 seconds')),
            DropdownMenuItem(value: 15, child: Text('15 seconds')),
            DropdownMenuItem(value: 30, child: Text('30 seconds')),
            DropdownMenuItem(value: 60, child: Text('1 minute')),
            DropdownMenuItem(value: 120, child: Text('2 minutes')),
            DropdownMenuItem(value: 300, child: Text('5 minutes')),
          ],
          onChanged: (v) {
            if (v != null) onRefreshIntervalChanged(v);
          },
        ),
        const SizedBox(height: 24),
        Card(
          child: SwitchListTile(
            title: const Text('Demo mode'),
            subtitle: const Text(
              'Shows bundled sample photos and albums instead of your '
              'library. Your real files are not affected.',
            ),
            value: demoMode,
            onChanged: onDemoModeChanged,
          ),
        ),
        // Drives are viewed, mounted and renamed on their own page; Settings
        // kept a second copy of that list until #2350.
        if (onOpenStorage != null) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              key: const ValueKey('settings_open_storage'),
              leading: const Icon(QuarkIcons.storage_rounded),
              title: const Text('Storage devices'),
              subtitle: const Text('View, mount and rename drives'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenStorage,
            ),
          ),
        ],
      ],
    );
  }
}
