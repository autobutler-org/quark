import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/local_trust_overrides_stub.dart'
    if (dart.library.io) 'package:quark/services/local_trust_overrides_io.dart';
import 'package:quark/utils/first_frame_gate.dart';
import 'package:quark/widgets/jobs/job_finish_announcer.dart';
import 'package:quark/widgets/jobs/jobs_badge_host.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/probe_bootstrap.dart';

/// Loads the saved settings, trusts the local Quark's self-signed certificate, starts the jobs watcher, and runs
/// the app, holding its first frame until the router has a page to show.
Future<void> main() async {
  usePathUrlStrategy();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  await maybeStartProbeAgent();
  await AppSettings.instance.load();
  // Quarks on the local network serve self-signed certificates. Install the
  // trust policy after settings load so it can consult the configured host.
  installLocalTrustHttpOverrides();
  // Finish announcements and the jobs list outlive every page.
  JobsController.instance.start();
  AuthService.watchAccount();
  deferFirstFrameUntilRouted(binding, router.routerDelegate);
  runApp(const QuarkApp());
}

/// The app's root messenger, so a snack bar raised outside any page — a job
/// finishing — shows on whatever page is open.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// The app's root: the theme, the router, and the job announcements and badge that sit above every page.
class QuarkApp extends StatelessWidget {
  const QuarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.instance.themeMode,
      builder: (context, mode, _) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Quark',
          theme: QuarkTheme.light(),
          darkTheme: QuarkTheme.dark(),
          themeMode: mode,
          routerConfig: router,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          builder: (context, child) => JobFinishAnnouncer(
            controller: JobsController.instance,
            messengerKey: rootScaffoldMessengerKey,
            onNavigate: router.go,
            child: JobsBadgeHost(
              controller: JobsController.instance,
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
