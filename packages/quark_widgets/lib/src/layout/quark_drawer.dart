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

  /// App settings.
  settings,
}

/// The app's navigation drawer: one row per [QuarkDrawerSection], with the
/// current one marked.
///
/// The drawer navigates nothing itself. Each row calls back and the page
/// routes, so the package stays free of the router.
///
/// The header names the Quark on screen when [hostName] is passed (#2033).
/// With more than one saved, the signed-in app otherwise said "Quark" and
/// nothing else, so which device a page was reading — or an upload was about
/// to land on — was invisible. The header is a button in that case:
/// [onTapHost] is where the caller sends someone who wants a different one.
///
/// Key prefixes: `drawer_<section>` on each row, for example `drawer_photos`,
/// and `drawer_host` on the header when it names a Quark.
///
/// ```dart
/// QuarkDrawer(
///   activeSection: QuarkDrawerSection.photos,
///   hostName: 'Home',
///   hostAddress: 'quark.home.local',
///   onTapHost: () => context.go(AppRoutes.settings),
///   onTapFiles: () => context.go(AppRoutes.files),
/// );
/// ```
class QuarkDrawer extends StatelessWidget {
  /// Creates a drawer with [activeSection] marked as current.
  const QuarkDrawer({
    required this.activeSection,
    this.hostName,
    this.hostAddress,
    this.onTapHost,
    this.onTapFiles,
    this.onTapPhotos,
    this.onTapTrash,
    this.onTapDocs,
    this.onTapSheets,
    this.onTapDevices,
    this.onTapHealth,
    this.onTapVault,
    this.onTapJobs,
    this.onTapSettings,
    super.key,
  });

  /// The page the drawer was opened from, drawn as selected.
  final QuarkDrawerSection activeSection;

  /// The nickname of the Quark being browsed, or null to show the product
  /// name alone — which is the honest header before a Quark is chosen.
  final String? hostName;

  /// The address under [hostName], already shortened for display by the
  /// caller. Ignored without a [hostName]: an address with no name to go with
  /// it is a diagnostic, not an identity.
  final String? hostAddress;

  /// Called when the header is tapped. Null leaves it as a label.
  final FutureOr<void> Function()? onTapHost;

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

  /// Called when the Jobs row is tapped.
  final FutureOr<void> Function()? onTapJobs;

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
            padding: EdgeInsets.zero,
            child: _header(context),
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
            QuarkDrawerSection.jobs,
            QuarkIcons.pending_actions_outlined,
            'Jobs',
            onTapJobs,
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

  /// The header: the product name, or the Quark on screen and how to leave it.
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final name = hostName;
    final onPrimary = theme.colorScheme.onPrimary;

    if (name == null || name.isEmpty) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Quark',
            style: theme.textTheme.titleLarge?.copyWith(color: onPrimary),
          ),
        ),
      );
    }

    final address = hostAddress ?? '';
    return InkWell(
      key: const ValueKey('drawer_host'),
      onTap: onTapHost == null ? null : () => onTapHost?.call(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quark',
              style: theme.textTheme.labelMedium?.copyWith(
                color: onPrimary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                // One line each, clipped with an ellipsis: a nickname is whatever someone
                // typed, and the drawer is 304dp wide on every phone.
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: onPrimary,
                    ),
                  ),
                ),
                if (onTapHost != null)
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 20,
                    color: onPrimary.withValues(alpha: 0.8),
                  ),
              ],
            ),
            if (address.isNotEmpty)
              Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onPrimary.withValues(alpha: 0.8),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
