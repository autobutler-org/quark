import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// The top-level destinations in [QuarkDrawer], one per main page.
enum QuarkDrawerSection {
  /// The file browser.
  files,

  /// The photo library.
  photos,

  /// Deleted files waiting to be restored or purged.
  trash,

  /// The document list.
  docs,

  /// The spreadsheet list.
  sheets,

  /// Storage devices attached to the Quark.
  devices,

  /// System health.
  health,

  /// The encrypted vault.
  vault,

  /// App settings.
  settings,
}

/// The app's navigation drawer: one row per [QuarkDrawerSection], with the
/// current one marked.
///
/// The drawer navigates nothing itself. Each row calls back and the page
/// routes, so the package stays free of the router.
///
/// Key prefixes: `drawer_<section>` on each row, for example `drawer_photos`.
///
/// ```dart
/// QuarkDrawer(
///   activeSection: QuarkDrawerSection.photos,
///   onTapFiles: () => context.go(AppRoutes.files),
/// );
/// ```
class QuarkDrawer extends StatelessWidget {
  /// Creates a drawer with [activeSection] marked as current.
  const QuarkDrawer({
    required this.activeSection,
    this.onTapFiles,
    this.onTapPhotos,
    this.onTapTrash,
    this.onTapDocs,
    this.onTapSheets,
    this.onTapDevices,
    this.onTapHealth,
    this.onTapVault,
    this.onTapSettings,
    super.key,
  });

  /// The page the drawer was opened from, drawn as selected.
  final QuarkDrawerSection activeSection;

  /// Called when the Files row is tapped.
  final FutureOr<void> Function()? onTapFiles;

  /// Called when the Photos row is tapped.
  final FutureOr<void> Function()? onTapPhotos;

  /// Called when the Trash row is tapped.
  final FutureOr<void> Function()? onTapTrash;

  /// Called when the Docs row is tapped.
  final FutureOr<void> Function()? onTapDocs;

  /// Called when the Sheets row is tapped.
  final FutureOr<void> Function()? onTapSheets;

  /// Called when the Devices row is tapped.
  final FutureOr<void> Function()? onTapDevices;

  /// Called when the Health row is tapped.
  final FutureOr<void> Function()? onTapHealth;

  /// Called when the Vault row is tapped.
  final FutureOr<void> Function()? onTapVault;

  /// Called when the Settings row is tapped.
  final FutureOr<void> Function()? onTapSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(
      QuarkDrawerSection section,
      IconData icon,
      String label,
      FutureOr<void> Function()? onTap,
    ) {
      return ListTile(
        key: ValueKey('drawer_${section.name}'),
        leading: Icon(icon),
        title: Text(label),
        selected: activeSection == section,
        onTap: () => onTap?.call(),
      );
    }

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: theme.colorScheme.primary),
            child: Text(
              'Quark',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          row(
            QuarkDrawerSection.files,
            QuarkIcons.storage_rounded,
            'Files',
            onTapFiles,
          ),
          row(
            QuarkDrawerSection.photos,
            QuarkIcons.photo_library_outlined,
            'Photos',
            onTapPhotos,
          ),
          row(
            QuarkDrawerSection.trash,
            QuarkIcons.delete_outline,
            'Trash',
            onTapTrash,
          ),
          row(
            QuarkDrawerSection.docs,
            QuarkIcons.description_outlined,
            'Docs',
            onTapDocs,
          ),
          row(
            QuarkDrawerSection.sheets,
            QuarkIcons.table_chart_outlined,
            'Sheets',
            onTapSheets,
          ),
          row(
            QuarkDrawerSection.devices,
            QuarkIcons.device_hub_outlined,
            'Devices',
            onTapDevices,
          ),
          row(
            QuarkDrawerSection.health,
            QuarkIcons.monitor_heart_outlined,
            'Health',
            onTapHealth,
          ),
          row(
            QuarkDrawerSection.vault,
            QuarkIcons.lock_outline,
            'Vault',
            onTapVault,
          ),
          row(
            QuarkDrawerSection.settings,
            QuarkIcons.settings_outlined,
            'Settings',
            onTapSettings,
          ),
        ],
      ),
    );
  }
}
