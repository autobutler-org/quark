import 'dart:async';

import 'package:autobutler/models/plugin_manifest.dart';
import 'package:flutter/material.dart';

enum AutobutlerDrawerSection {
  cirrus,
  photos,
  devices,
  health,
  settings,
  plugins,
  plugin,
}

class AutobutlerDrawer extends StatelessWidget {
  const AutobutlerDrawer({
    super.key,
    required this.activeSection,
    this.onTapCirrus,
    this.onTapPhotos,
    this.onTapDevices,
    this.onTapHealth,
    this.onTapSettings,
    this.onTapPlugins,
    this.plugins = const [],
    this.activePluginId,
    this.onTapPlugin,
  });

  final AutobutlerDrawerSection activeSection;
  final FutureOr<void> Function()? onTapCirrus;
  final FutureOr<void> Function()? onTapPhotos;
  final FutureOr<void> Function()? onTapDevices;
  final FutureOr<void> Function()? onTapHealth;
  final FutureOr<void> Function()? onTapSettings;
  final FutureOr<void> Function()? onTapPlugins;

  /// Plugin manifests to append to the drawer after the built-in items.
  final List<PluginManifest> plugins;

  /// The ID of the currently active plugin (if any).
  final String? activePluginId;

  /// Called when a plugin nav item is tapped.
  final void Function(PluginManifest plugin)? onTapPlugin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: theme.colorScheme.primary),
            child: Text(
              'Autobutler',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage_rounded),
            title: const Text('Files'),
            selected: activeSection == AutobutlerDrawerSection.cirrus,
            onTap: () {
              onTapCirrus?.call();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photos'),
            selected: activeSection == AutobutlerDrawerSection.photos,
            onTap: () {
              onTapPhotos?.call();
            },
          ),
          ListTile(
            leading: const Icon(Icons.device_hub_outlined),
            title: const Text('Devices'),
            selected: activeSection == AutobutlerDrawerSection.devices,
            onTap: () {
              onTapDevices?.call();
            },
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Health'),
            selected: activeSection == AutobutlerDrawerSection.health,
            onTap: () {
              onTapHealth?.call();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            selected: activeSection == AutobutlerDrawerSection.settings,
            onTap: () {
              onTapSettings?.call();
            },
          ),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('Plugins'),
            selected: activeSection == AutobutlerDrawerSection.plugins,
            onTap: () {
              onTapPlugins?.call();
            },
          ),
          // Installed plugin nav items appended after built-in items.
          for (final plugin in plugins)
            if (plugin.contributes.navItem != null)
              ListTile(
                leading: Icon(_iconFromName(plugin.contributes.navItem!.icon)),
                title: Text(plugin.contributes.navItem!.label),
                selected:
                    activeSection == AutobutlerDrawerSection.plugin &&
                    activePluginId == plugin.id,
                onTap: () => onTapPlugin?.call(plugin),
              ),
        ],
      ),
    );
  }

  /// Public accessor so external widgets can resolve icon names.
  static IconData iconFromName(String name) => _iconFromName(name);

  /// Resolves a Material icon by name string.
  /// Falls back to [Icons.extension] for unknown names.
  static IconData _iconFromName(String name) {
    const map = <String, IconData>{
      'waving_hand': Icons.waving_hand,
      'extension': Icons.extension,
      'download': Icons.download,
      'settings': Icons.settings,
      'folder': Icons.folder,
      'photo': Icons.photo,
      'health': Icons.monitor_heart_outlined,
    };
    return map[name] ?? Icons.extension;
  }
}
