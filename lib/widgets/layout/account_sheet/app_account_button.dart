import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/controllers/upload_sessions_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/settings_service.dart';
import 'package:quark/widgets/layout/account_sheet/account_dot.dart';
import 'package:quark/widgets/layout/connection_sheet_button.dart';
import 'package:quark/widgets/notifications/notifications_list.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The phone app bar's one app-wide control (#4150): a [QuarkAccountButton]
/// wired to the app, opening a [QuarkAccountSheet] with the notifications,
/// the running jobs, the connection, the theme and the switch to another
/// Quark.
///
/// The dot follows [accountDotShown]: an unread notification, a running job
/// or upload, or remote access paused or offline.
///
/// Like the bell and the connection pill it replaces on a phone, it sits in
/// every main page's bar below the navigator, so it opens the sheet from its
/// own context and leaves routes to [onNavigate].
///
/// Keys: those of [QuarkAccountButton] and [QuarkAccountSheet].
class AppAccountButton extends StatelessWidget {
  /// Creates the account button.
  const AppAccountButton({
    required this.jobs,
    required this.notifications,
    required this.onNavigate,
    this.uploads,
    this.connection,
    this.paused = false,
    super.key,
  });

  /// Where the running job count comes from.
  final JobsController jobs;

  /// Where the count of uploads in flight comes from; they count as jobs.
  final UploadSessionsController? uploads;

  /// Where the notifications come from.
  final NotificationsController notifications;

  /// The wide bar's connection pill, whose panel the sheet shows. Null, on
  /// the web or with no Quark configured, leaves the section out.
  final ConnectionSheetButton? connection;

  /// Whether remote access is paused on this phone, which shows the dot.
  final bool paused;

  /// Opens a route. The root passes the router's own `go`.
  final ValueChanged<String> onNavigate;

  int get _running => jobs.runningCount + (uploads?.activeCount ?? 0);

  void _open(BuildContext context) {
    // A backup goes stale with time alone, so opening the sheet asks again,
    // as the bell does.
    if (notifications.isSignedIn) unawaited(notifications.load());
    final settings = AppSettings.instance;
    final connection = this.connection;
    void go(BuildContext sheetContext, String route) {
      Navigator.of(sheetContext).pop();
      onNavigate(route);
    }

    showQuarkSheet<void>(
      context,
      title: 'Account',
      builder: (sheetContext) => ListenableBuilder(
        listenable: Listenable.merge([
          jobs,
          ?uploads,
          notifications,
          settings.themeMode,
          settings.activeHostNotifier,
        ]),
        builder: (sheetContext, _) => QuarkAccountSheet(
          notifications: notifications.isSignedIn
              ? NotificationsList(
                  controller: notifications,
                  onOpen: (notification) => go(sheetContext, notification.link),
                )
              : null,
          runningJobs: _running,
          onOpenJobs: () =>
              go(sheetContext, AppRoutes.systemTab(SystemTab.jobs)),
          connection: connection?.sheet(context, sheetContext),
          themeMode: settings.themeMode.value,
          onThemeModeChanged: (mode) =>
              SettingsService.logFailure(SettingsService.setMyThemeMode(mode)),
          quarkName: settings.activeHostEntry?.name ?? 'No Quark',
          onSwitchQuark: () =>
              go(sheetContext, AppRoutes.settingsTab(SettingsTab.general)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([jobs, ?uploads, notifications]),
      builder: (context, _) => QuarkAccountButton(
        showDot: accountDotShown(
          notifications: notifications.isSignedIn
              ? notifications.notifications.length
              : 0,
          running: _running,
          mode: connection?.mode,
          paused: paused,
        ),
        onPressed: () => _open(context),
      ),
    );
  }
}
