import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/services/embedded_tunnel.dart';
import 'package:quark/router.dart';
import 'package:quark/widgets/layout/connection_sheet_button.dart';
import 'package:quark/widgets/layout/remote_access_pause_banner.dart';
import 'package:quark/widgets/notifications/notifications_bell.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Gives every main page's top bar the app-wide controls, through one
/// [QuarkAppBarTrailing] scope at the app root: a [ConnectionSheetButton] fed
/// by [connection] (#1880), which opens the connection sheet (#2857), a
/// [JobsBadge] counting [jobs]' running jobs, and a [NotificationsBell]
/// counting [notifications]' entries and opening them (#2493).
///
/// The indicator is left out until [connection] has a mode, which is never on
/// web and never with no Quark configured. While remote access is paused on
/// a device that runs a node, the pill still shows, the pages gain a banner
/// under the app bar, and an unreachable page offers to turn it back on
/// (#2876). Desktop has no node, so that switch, banner, and chip stay
/// hidden (#3779). The bell renders nothing while nobody is signed in.
class AppBarTrailingHost extends StatefulWidget {
  /// Creates the scope around [child].
  const AppBarTrailingHost({
    required this.jobs,
    required this.connection,
    required this.notifications,
    required this.onNavigate,
    required this.child,
    super.key,
  });

  /// Where the running count comes from.
  final JobsController jobs;

  /// Where the local, remote or offline state comes from.
  final ConnectionController connection;

  /// Where the bell's notifications come from.
  final NotificationsController notifications;

  /// Opens a route. The root sits above the navigator, so the app passes the
  /// router's own `go` rather than a context lookup.
  final ValueChanged<String> onNavigate;

  /// The rest of the app.
  final Widget child;

  @override
  State<AppBarTrailingHost> createState() => _AppBarTrailingHostState();
}

class _AppBarTrailingHostState extends State<AppBarTrailingHost> {
  @override
  void dispose() {
    QuarkPageScaffold.pauseBanner = null;
    QuarkDisconnectedView.turnOnRemoteAccess = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final mode = connection.mode;
        final onDevice = EmbeddedTunnel.runsOnDeviceNode;
        final paused = onDevice && connection.remoteAccessPaused;
        QuarkPageScaffold.pauseBanner = (context) =>
            paused ? RemoteAccessPauseBanner(controller: connection) : null;
        QuarkDisconnectedView.turnOnRemoteAccess = paused
            ? () => unawaited(connection.resumeRemoteAccess())
            : null;
        return QuarkAppBarTrailing(
          actions: [
            if (mode != null || paused)
              ConnectionSheetButton(
                mode: mode ?? ConnectionMode.offline,
                paused: paused,
                pairingError: onDevice ? connection.pairingError : null,
                onPause: onDevice ? connection.pause : null,
                onResume: onDevice ? connection.resumeRemoteAccess : null,
                onNavigate: widget.onNavigate,
              ),
            ListenableBuilder(
              listenable: widget.jobs,
              builder: (context, _) => JobsBadge(
                runningCount: widget.jobs.runningCount,
                onTap: () =>
                    widget.onNavigate(AppRoutes.systemTab(SystemTab.jobs)),
              ),
            ),
            NotificationsBell(
              controller: widget.notifications,
              onNavigate: widget.onNavigate,
            ),
          ],
          child: widget.child,
        );
      },
    );
  }
}
