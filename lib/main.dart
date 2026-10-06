import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/local_trust_overrides_stub.dart'
    if (dart.library.io) 'package:quark/services/local_trust_overrides_io.dart';
import 'package:quark/utils/first_frame_gate.dart';
import 'package:quark/widgets/jobs/job_finish_announcer.dart';
import 'package:quark/widgets/layout/app_bar_trailing_host.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/probe_bootstrap.dart';

/// Loads the saved settings, trusts the local Quark's self-signed certificate, starts the jobs watcher, and runs
/// the app, holding its first frame until the router has a page to show.
Future<void> main() async {
  usePathUrlStrategy();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Flutter web builds the semantics tree only after someone finds its hidden
  // "Enable accessibility" button, so screen readers see nothing until then
  // (#2599). The handle is never disposed: the tree lives as long as the app.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  await maybeStartProbeAgent();
  await AppSettings.instance.load();
  // Quarks on the local network serve self-signed certificates. Install the
  // trust policy after settings load so it can consult the configured host.
  installLocalTrustHttpOverrides();
  // Finish announcements and the jobs list outlive every page.
  JobsController.instance.start();
  // Picks the home or remote-access address before the first request goes
  // out, and keeps picking (#1880).
  ConnectionController.instance.start();
  AuthService.watchAccount();
  // Not awaited: a cached chat identity is not worth holding the first frame.
  ChatKeysController.instance.start();
  // Shares channel keys with members who are waiting for them (#2417).
  ChatChannelKeysController.instance.start();
  // A right-click opens an item's own menu everywhere it has one (#2276), so
  // the browser's menu is turned off once, for the whole app. Text fields
  // fall back to Flutter's own copy/paste menu.
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  deferFirstFrameUntilRouted(binding, router.routerDelegate);
  runApp(const QuarkApp());
}

/// The app's root messenger, so a snack bar raised outside any page — a job
/// finishing — shows on whatever page is open.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// The app's root: the theme, the router, and the job announcements, jobs badge and connection indicator that sit
/// above every page.
class QuarkApp extends StatelessWidget {
  const QuarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([settings.themeMode, settings.themeColor]),
      builder: (context, _) {
        final themeColor = settings.themeColor.value;
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Quark',
          theme: QuarkTheme.light(themeColor: themeColor),
          darkTheme: QuarkTheme.dark(themeColor: themeColor),
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
              onNavigate: router.go,
              child: child ?? const SizedBox.shrink(),
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
