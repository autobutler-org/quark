import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/file_browser_cache.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/controllers/vault_biometric_controller.dart';
import 'package:quark/controllers/vault_cache_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/download_notices.dart';
import 'package:quark/services/local_trust_overrides_stub.dart'
    if (dart.library.io) 'package:quark/services/local_trust_overrides_io.dart';
import 'package:quark/services/video_playback_backend.dart';
import 'package:quark/utils/app_log.dart';
import 'package:quark/utils/first_frame_gate.dart';
import 'package:quark/utils/startup.dart';
import 'package:quark/utils/startup_config.dart';
import 'package:quark/widgets/jobs/job_finish_announcer.dart';
import 'package:quark/widgets/layout/app_bar_trailing_host.dart';
import 'package:quark/widgets/layout/startup_loader.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/probe_bootstrap.dart';

/// Runs the app with every uncaught error recorded in the app log on this device's own disk (#1822).
void main() => AppLog.instance.guard(_run);

/// Loads the saved settings, trusts the local Quark's self-signed certificate, starts the jobs and notifications
/// watchers, and runs the app, holding its first frame until the router has a page to show.
///
/// Neither wait is open-ended (#2066): settings slower than [StartupConfig.settingsGrace] get a [StartupLoader]
/// painted meanwhile, and the first frame is held for at most [StartupConfig.firstFrameMaxHold].
Future<void> _run() async {
  AppLog.instance.info('App started');
  usePathUrlStrategy();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Linux has no video_player backend of its own (#3151).
  installVideoPlaybackBackend();
  await maybeStartProbeAgent();
  // The native launch screen is blank, and nothing is painted until the
  // settings are in. A load that stalls, say on the secure-storage read, now
  // shows a loader instead of that blank screen (#2066).
  await awaitWithSlowNotice(
    AppSettings.instance.load(),
    grace: StartupConfig.settingsGrace,
    onSlow: () => runApp(const StartupLoader()),
  );
  // What the last launch left on disk shows while the first listing loads
  // (#1781). Not awaited: a snapshot is not worth holding the first frame.
  unawaited(FileBrowserCache.instance.hydrate());
  // Quarks on the local network serve self-signed certificates. Install the
  // trust policy after settings load so it can consult the configured host.
  installLocalTrustHttpOverrides();
  // Finish announcements and the jobs list outlive every page.
  JobsController.instance.start();
  // The bell's count is right on whatever page opens first (#2493).
  NotificationsController.instance.start();
  // Picks the home or remote-access address before the first request goes
  // out, and keeps picking (#1880).
  ConnectionController.instance.start();
  AuthService.watchAccount();
  // Not awaited: a cached chat identity is not worth holding the first frame.
  ChatKeysController.instance.start();
  // Shares channel keys with members who are waiting for them (#2417).
  ChatChannelKeysController.instance.start();
  // Keeps the vault's ciphertext where native autofill can read it (#3596).
  VaultCacheController.instance.start(vault: VaultController.instance);
  // Unlocks the vault with a face or fingerprint where turned on, and
  // deletes the cached key when the account or the vault changes (#3595).
  VaultBiometricController.instance.start(vault: VaultController.instance);
  // A right-click opens an item's own menu everywhere it has one (#2276), so
  // the browser's menu is turned off once, for the whole app. Text fields
  // fall back to Flutter's own copy/paste menu.
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  // Says why a picture went to Files rather than Photos (#3334), on whatever
  // page started the download.
  downloadNotices.listen(
    (message) => rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    ),
  );
  deferFirstFrameUntilRouted(binding, router.routerDelegate);
  runApp(const QuarkApp());
}

/// The app's root messenger, so a snack bar raised outside any page — a job
/// finishing — shows on whatever page is open.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// The app's root: the theme, the router, and the job announcements, jobs badge, notifications bell and connection indicator that sit
/// above every page.
class QuarkApp extends StatelessWidget {
  const QuarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        settings.themeMode,
        settings.themeColor,
        settings.highContrast,
        settings.leftHanded,
      ]),
      builder: (context, _) {
        final themeColor = settings.themeColor.value;
        // The platform's contrast setting picks the high-contrast pair on its
        // own; the Settings switch, for platforms without one, picks it for
        // the everyday slots too (#2601). Both pairs follow the theme color
        // (#3071).
        final highContrastLight = QuarkTheme.highContrastLight(
          themeColor: themeColor,
        );
        final highContrastDark = QuarkTheme.highContrastDark(
          themeColor: themeColor,
        );
        final highContrast = settings.highContrast.value;
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Quark',
          theme: highContrast
              ? highContrastLight
              : QuarkTheme.light(themeColor: themeColor),
          darkTheme: highContrast
              ? highContrastDark
              : QuarkTheme.dark(themeColor: themeColor),
          highContrastTheme: highContrastLight,
          highContrastDarkTheme: highContrastDark,
          themeMode: settings.themeMode.value,
          routerConfig: router,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          builder: (context, child) => JobFinishAnnouncer(
            controller: JobsController.instance,
            messengerKey: rootScaffoldMessengerKey,
            onNavigate: router.go,
            child: AppBarTrailingHost(
              jobs: JobsController.instance,
              connection: ConnectionController.instance,
              notifications: NotificationsController.instance,
              onNavigate: router.go,
              // Every page's bar, drawer and floating button reads this, so
              // the whole app mirrors from the one setting (#1812).
              child: QuarkHandedness(
                leftHanded: settings.leftHanded.value,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
        );
      },
    );
  }
}
