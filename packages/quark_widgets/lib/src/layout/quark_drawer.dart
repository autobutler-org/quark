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

  /// Long-running jobs on the Quark, such as video conversions.
  jobs,

  /// The accounts on the Quark.
  users,

  /// App settings.
  settings,
}

/// The app's navigation drawer: one row per [QuarkDrawerSection] the caller
/// offers, with the current one marked.
///
/// The drawer navigates nothing itself. Each row calls back and the page
/// routes, so the package stays free of the router.
///
/// A row is drawn only when its callback is set. That is how a caller hides a
/// destination the signed-in user cannot use, such as Users or Vault for
/// someone who is not an admin, rather than showing a row that goes nowhere.
///
/// Key prefixes: `drawer_<section>` on each row, for example `drawer_photos`
/// and `drawer_users`.
///
/// ```dart
/// QuarkDrawer(
///   activeSection: QuarkDrawerSection.photos,
///   onTapFiles: () => context.go(AppRoutes.files),
///   onTapUsers: isAdmin ? () => context.go(AppRoutes.users) : null,
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
    this.onTapJobs,
    this.onTapUsers,
    this.onTapSettings,
    super.key,
  });

  /// The page the drawer was opened from, drawn as selected.
  final QuarkDrawerSection activeSection;

  /// Called when the Files row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapFiles;

  /// Called when the Photos row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapPhotos;

  /// Called when the Trash row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapTrash;

  /// Called when the Docs row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapDocs;

  /// Called when the Sheets row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapSheets;

  /// Called when the Devices row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapDevices;

  /// Called when the Health row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapHealth;

  /// Called when the Vault row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapVault;

  /// Called when the Jobs row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapJobs;

  /// Called when the Users row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapUsers;

  /// Called when the Settings row is tapped. Null hides the row.
  final FutureOr<void> Function()? onTapSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      (
        QuarkDrawerSection.files,
        QuarkIcons.storage_rounded,
        'Files',
        onTapFiles,
      ),
      (
        QuarkDrawerSection.photos,
        QuarkIcons.photo_library_outlined,
        'Photos',
        onTapPhotos,
      ),
      (
        QuarkDrawerSection.trash,
        QuarkIcons.delete_outline,
        'Trash',
        onTapTrash,
      ),
      (
        QuarkDrawerSection.docs,
        QuarkIcons.description_outlined,
        'Docs',
        onTapDocs,
      ),
      (
        QuarkDrawerSection.sheets,
        QuarkIcons.table_chart_outlined,
        'Sheets',
        onTapSheets,
      ),
      (
        QuarkDrawerSection.devices,
        QuarkIcons.device_hub_outlined,
        'Devices',
        onTapDevices,
      ),
      (
        QuarkDrawerSection.health,
        QuarkIcons.monitor_heart_outlined,
        'Health',
        onTapHealth,
      ),
      (QuarkDrawerSection.vault, QuarkIcons.lock_outline, 'Vault', onTapVault),
      (
        QuarkDrawerSection.jobs,
        QuarkIcons.pending_actions_outlined,
        'Jobs',
        onTapJobs,
      ),
      (
        QuarkDrawerSection.users,
        QuarkIcons.person_outline,
        'Users',
        onTapUsers,
      ),
      (
        QuarkDrawerSection.settings,
        QuarkIcons.settings_outlined,
        'Settings',
        onTapSettings,
      ),
    ];

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
          for (final (section, icon, label, onTap) in rows)
            if (onTap != null)
              ListTile(
                key: ValueKey('drawer_${section.name}'),
                leading: Icon(icon),
                title: Text(label),
                selected: activeSection == section,
                onTap: onTap,
              ),
        ],
      ),
    );
  }
}
