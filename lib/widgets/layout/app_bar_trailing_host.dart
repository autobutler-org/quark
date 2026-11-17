import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/upload_sessions_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/connection_config.dart';
import 'package:quark/widgets/layout/account_sheet/app_account_button.dart';
import 'package:quark/widgets/layout/connection_sheet_button.dart';
import 'package:quark/widgets/layout/remote_access_pause_banner.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/notifications/notifications_bell.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:tailnet_flutter/tailnet_flutter.dart';

/// Gives every main page's top bar the app-wide controls, through one
/// [QuarkAppBarTrailing] scope at the app root: the [AppThemeToggle] each
/// page used to append itself (#4150), a [ConnectionSheetButton] fed
/// by [connection] (#1880), which opens the connection sheet (#2857), a
/// [JobsBadge] counting [jobs]' running jobs and [uploads]' uploads in
/// flight, and a [NotificationsBell]
/// counting [notifications]' entries and opening them (#2493).
///
/// The indicator is left out until [connection] has a mode, which is never on
/// web and never with no Quark configured. While remote access is paused on
/// a device that runs a node, the pill still shows, the pages gain a banner
/// under the app bar, and an unreachable page offers to turn it back on
/// (#2876). Desktop has no node, so that switch, banner, and chip stay
/// hidden (#3779). The bell renders nothing while nobody is signed in.
///
/// A phone's bar has no room for the three, so the scope's compact control
/// is one [AppAccountButton] whose sheet holds them all, with the theme and
/// the switch to another Quark (#4150).
///
/// It is also the one place that decides whether a page that could not
/// load is offline (#3881). A [QuarkDisconnectedView] or
/// [QuarkDisconnectedBanner] coming on screen asks [connection] to check,
/// once however many pages failed together. While that check runs, and
/// whenever the connection says the Quark is reachable, those screens say
/// they are reconnecting rather than offline, and every one of them loads
/// again by itself when a check finds the Quark, or when an offline Quark
/// comes back. Off the web they name the way the app reaches the Quark,
/// never its home address, and a phone always shows its own reason rather
/// than the home Wi-Fi checklist.
class AppBarTrailingHost extends StatefulWidget {
  /// Creates the scope around [child].
  const AppBarTrailingHost({
    required this.jobs,
    this.uploads,
    required this.connection,
    required this.notifications,
    required this.onNavigate,
    required this.child,
    @visibleForTesting bool? runsOnDeviceNode,
    super.key,
  }) : _runsOnDeviceNode = runsOnDeviceNode;

  /// How long after a check the screens still showing check again. Doubles
  /// each time, up to [ConnectionConfig.offlineBackoffMax].
  static const Duration recheckWhileShown = Duration(seconds: 5);

  final bool? _runsOnDeviceNode;

  /// Where the running count comes from.
  final JobsController jobs;

  /// Where the count of uploads in flight comes from. They count toward the
  /// badge alongside running jobs, and both open the Jobs tab (#3972).
  final UploadSessionsController? uploads;

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
  bool _checking = false;
  Timer? _recheck;
  Duration _recheckDelay = AppBarTrailingHost.recheckWhileShown;
  ConnectionMode? _lastMode;

  bool get _onDevice =>
      widget._runsOnDeviceNode ?? EmbeddedTunnel.runsOnDeviceNode;

  static bool _reachable(ConnectionMode? mode) =>
      mode == ConnectionMode.local || mode == ConnectionMode.remote;

  @override
  void initState() {
    super.initState();
    _lastMode = widget.connection.mode;
    widget.connection.addListener(_onConnectionChanged);
    // The web app has no connection to check: the browser already found it.
    if (!kIsWeb) QuarkDisconnectedView.onShown = _checkForShown;
  }

  @override
  void dispose() {
    widget.connection.removeListener(_onConnectionChanged);
    _recheck?.cancel();
    QuarkPageScaffold.pauseBanner = null;
    QuarkDisconnectedView.turnOnRemoteAccess = null;
    QuarkDisconnectedView.reason = null;
    QuarkDisconnectedView.onShown = null;
    QuarkDisconnectedView.reconnecting = false;
    QuarkDisconnectedView.route = null;
    super.dispose();
  }

  /// An offline Quark that answers again reloads every screen that gave up.
  void _onConnectionChanged() {
    final mode = widget.connection.mode;
    final cameBack = !_reachable(_lastMode) && _reachable(mode);
    _lastMode = mode;
    if (cameBack && !_checking) QuarkDisconnectedView.retryShown();
  }

  /// Checks once for every screen that just failed. Another screen failing
  /// while a check runs, or before the next one is due, joins that check.
  void _checkForShown() {
    if (_checking || _recheck != null) return;
    unawaited(_checkAndRetry());
  }

  Future<void> _checkAndRetry() async {
    setState(() => _checking = true);
    await widget.connection.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (_reachable(widget.connection.mode)) {
      QuarkDisconnectedView.retryShown();
    }
    _recheck = Timer(_recheckDelay, () {
      _recheck = null;
      if (QuarkDisconnectedView.showing) {
        _checkForShown();
      } else {
        _recheckDelay = AppBarTrailingHost.recheckWhileShown;
      }
    });
    final doubled = _recheckDelay * 2;
    _recheckDelay = doubled > ConnectionConfig.offlineBackoffMax
        ? ConnectionConfig.offlineBackoffMax
        : doubled;
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final mode = connection.mode;
        final onDevice = _onDevice;
        final paused = onDevice && connection.remoteAccessPaused;
        QuarkPageScaffold.pauseBanner = (context) =>
            paused ? RemoteAccessPauseBanner(controller: connection) : null;
        QuarkDisconnectedView.turnOnRemoteAccess = paused
            ? () => unawaited(connection.resumeRemoteAccess())
            : null;
        QuarkDisconnectedView.reason = quarkUnreachableReason(
          onDevice: onDevice,
          paused: connection.remoteAccessPaused,
          phone: connection.phoneRemoteAccess,
        );
        QuarkDisconnectedView.reconnecting =
            !kIsWeb && (_checking || _reachable(mode));
        QuarkDisconnectedView.route = quarkRouteLabel(
          onDevice: onDevice,
          mode: mode,
        );
        final connectionButton = mode != null || paused
            ? ConnectionSheetButton(
                mode: mode ?? ConnectionMode.offline,
                paused: paused,
                thisPhoneOn: connection.remoteAccessOnThisPhone,
                pairingError: onDevice ? connection.pairingError : null,
                phoneStatus: onDevice
                    ? connection.phoneRemoteAccessDetail
                    : null,
                offlineReason: onDevice ? connection.offlineReason : null,
                onPause: onDevice ? connection.pause : null,
                onResume: onDevice ? connection.resumeRemoteAccess : null,
                onNavigate: widget.onNavigate,
              )
            : null;
        return QuarkAppBarTrailing(
          actions: [
            // Where every page's own theme toggle used to end its actions.
            const AppThemeToggle(),
            ?connectionButton,
            ListenableBuilder(
              listenable: Listenable.merge([widget.jobs, ?widget.uploads]),
              builder: (context, _) => JobsBadge(
                runningCount:
                    widget.jobs.runningCount +
                    (widget.uploads?.activeCount ?? 0),
                onTap: () =>
                    widget.onNavigate(AppRoutes.systemTab(SystemTab.jobs)),
              ),
            ),
            NotificationsBell(
              controller: widget.notifications,
              onNavigate: widget.onNavigate,
            ),
          ],
          compact: AppAccountButton(
            jobs: widget.jobs,
            uploads: widget.uploads,
            notifications: widget.notifications,
            connection: connectionButton,
            paused: paused,
            onNavigate: widget.onNavigate,
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// Which away-screen reason a phone already knows, or null when this device
/// is not a phone.
///
/// A browser cannot use remote access, so it keeps the checklist. A phone
/// never does (#3881): a page can fail while the connection still reads
/// reachable, and the home Wi-Fi checklist is wrong advice for a phone away
/// from home. The screen can also say there is no internet or that the
/// network wants a sign-in; those are passed in by whoever measured them.
/// This returns only the three a [ConnectionController] can already tell
/// apart: not set up, paused, or the Quark not answering.
QuarkUnreachableReason? quarkUnreachableReason({
  required bool onDevice,
  required bool paused,
  required PhoneRemoteAccess phone,
}) {
  if (!onDevice) return null;
  if (paused) return QuarkUnreachableReason.paused;
  if (phone == PhoneRemoteAccess.notSetUp) {
    return QuarkUnreachableReason.notSetUp;
  }
  return QuarkUnreachableReason.notAnswering;
}

/// How the app reaches the Quark, in words for the disconnected screens, in
/// place of the home address they used to show (#3881).
///
/// Null keeps the address the page passed, which a browser and a desktop
/// without a way to the Quark do. A phone that cannot reach it shows no
/// address at all: its reason already says what is wrong, and the home
/// address reads as the app trying the wrong place.
String? quarkRouteLabel({
  required bool onDevice,
  required ConnectionMode? mode,
}) => switch (mode) {
  ConnectionMode.local => 'Using your home network',
  ConnectionMode.remote => 'Using remote access',
  _ => onDevice ? '' : null,
};
