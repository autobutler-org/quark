import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/plugin_state.dart';
import 'package:quark/utils/plugin_icons.dart';
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
/// Chat and Calendar are offered while an admin has their beta on, following
/// [AppSettings.featureFlags]; the router asks the Quark again before it opens
/// the page.
///
/// Every installed plugin with a nav item gets a row below the pages,
/// following [PluginState]; [activePluginId] marks the one on screen.
///
/// The header names the active Quark (#2033) and, with more than one saved,
/// switches between them (#2230). Switching goes through login: the router's
/// gate forwards a Quark you are signed in to on to Files, and one you are
/// not to its sign-in or setup page.
class AppDrawer extends StatelessWidget {
  /// Creates the drawer for the page [activeSection] names.
  const AppDrawer({
    required this.activeSection,
    this.activePluginId,
    super.key,
  });

  /// The page the drawer is opened from.
  final QuarkDrawerSection activeSection;

  /// The plugin whose page the drawer is opened from, if it is one.
  final String? activePluginId;

  @override
  Widget build(BuildContext context) {
    VoidCallback goTo(QuarkDrawerSection section, String route) =>
        section == activeSection
        ? () => Navigator.of(context).pop()
        : () => context.go(route);

    final settings = AppSettings.instance;

    Future<void> selectHost(int index) async {
      // Captured first: the drawer's context is gone once it closes.
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      if (index == settings.activeIndex) return;
      await settings.setActiveIndex(index);
      router.go(AppRoutes.login);
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        settings.isAdmin,
        settings.featureFlags,
        settings.activeHostNotifier,
        PluginState.instance,
      ]),
      builder: (context, _) => QuarkDrawer(
        activeSection: activeSection,
        hosts: [
          for (final host in settings.hosts)
            HostItem(
              name: host.name,
              address: shortHostAddress(host.hostAddress),
            ),
        ],
        activeHostIndex: settings.activeIndex,
        onSelectHost: selectHost,
        onTapFiles: goTo(QuarkDrawerSection.files, AppRoutes.files),
        onTapPhotos: goTo(QuarkDrawerSection.photos, AppRoutes.photos),
        onTapCalendar: settings.isFeatureEnabled(FeatureFlag.calendar)
            ? goTo(QuarkDrawerSection.calendar, AppRoutes.calendar)
            : null,
        onTapTrash: goTo(QuarkDrawerSection.trash, AppRoutes.trash),
        onTapDocs: goTo(QuarkDrawerSection.docs, AppRoutes.docs),
        onTapSheets: goTo(QuarkDrawerSection.sheets, AppRoutes.sheets),
        onTapChat: settings.isFeatureEnabled(FeatureFlag.chat)
            ? goTo(QuarkDrawerSection.chat, AppRoutes.chat)
            : null,
        onTapSystem: goTo(QuarkDrawerSection.system, AppRoutes.system),
        onTapVault: settings.isAdmin.value
            ? goTo(QuarkDrawerSection.vault, AppRoutes.vault)
            : null,
        onTapUsers: settings.isAdmin.value
            ? goTo(QuarkDrawerSection.users, AppRoutes.users)
            : null,
        onTapSettings: goTo(QuarkDrawerSection.settings, AppRoutes.settings),
        // A plugin's page sits under Plugins, so from there the row navigates.
        onTapPlugins: activePluginId == null
            ? goTo(QuarkDrawerSection.plugins, AppRoutes.plugins)
            : () => context.go(AppRoutes.plugins),
        plugins: [
          for (final plugin in PluginState.instance.plugins)
            if (plugin.contributes.navItem case final navItem?)
              DrawerPluginItem(
                id: plugin.id,
                label: navItem.label,
                icon: pluginIcon(navItem.icon),
              ),
        ],
        activePluginId: activePluginId,
        onTapPlugin: (id) => id == activePluginId
            ? Navigator.of(context).pop()
            : context.go(AppRoutes.pluginPath(id)),
      ),
    );
  }
}
