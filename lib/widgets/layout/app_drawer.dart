import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/host_display.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// [QuarkDrawer] wired to the router, so every top-level page opens the same
/// drawer.
///
/// Every top-level page used to build the drawer itself, row by row, so a new
/// destination meant the same edit on every page, and one missed left that
/// page's drawer without it. Each
/// row goes to its page with `context.go`; the row for the page the drawer
/// was opened from closes the drawer instead.
///
/// Admin-only pages are offered to admins only, following
/// [AppSettings.isAdmin]. That decides what the drawer shows and nothing
/// more: the router checks with the Quark before it opens one of those pages,
/// and the Quark refuses their requests from anyone else.
///
/// The header names the active Quark (#2033).
class AppDrawer extends StatelessWidget {
  /// Creates the drawer for the page [activeSection] names.
  const AppDrawer({required this.activeSection, super.key});

  /// The page the drawer is opened from.
  final QuarkDrawerSection activeSection;

  @override
  Widget build(BuildContext context) {
    VoidCallback goTo(QuarkDrawerSection section, String route) =>
        section == activeSection
        ? () => Navigator.of(context).pop()
        : () => context.go(route);

    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.instance.isAdmin,
      builder: (context, isAdmin, _) => QuarkDrawer(
        activeSection: activeSection,
        hostName: AppSettings.instance.activeHostName,
        hostAddress: shortHostAddress(AppSettings.instance.activeHost),
        onTapFiles: goTo(QuarkDrawerSection.files, AppRoutes.files),
        onTapPhotos: goTo(QuarkDrawerSection.photos, AppRoutes.photos),
        onTapTrash: goTo(QuarkDrawerSection.trash, AppRoutes.trash),
        onTapDocs: goTo(QuarkDrawerSection.docs, AppRoutes.docs),
        onTapSheets: goTo(QuarkDrawerSection.sheets, AppRoutes.sheets),
        onTapDevices: goTo(QuarkDrawerSection.devices, AppRoutes.devices),
        onTapHealth: goTo(QuarkDrawerSection.health, AppRoutes.health),
        onTapVault: isAdmin
            ? goTo(QuarkDrawerSection.vault, AppRoutes.vault)
            : null,
        onTapJobs: goTo(QuarkDrawerSection.jobs, AppRoutes.jobs),
        onTapUsers: isAdmin
            ? goTo(QuarkDrawerSection.users, AppRoutes.users)
            : null,
        onTapSettings: goTo(QuarkDrawerSection.settings, AppRoutes.settings),
      ),
    );
  }
}
