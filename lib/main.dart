import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/local_trust_overrides_stub.dart'
    if (dart.library.io) 'package:quark/services/local_trust_overrides_io.dart';
import 'package:quark/widgets/jobs/job_finish_announcer.dart';
import 'package:quark/widgets/jobs/jobs_badge_host.dart';
import 'package:quark_widgets/quark_widgets.dart';

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  // Quarks on the local network serve self-signed certificates. Install the
  // trust policy after settings load so it can consult the configured host.
  installLocalTrustHttpOverrides();
  // Finish announcements and the jobs list outlive every page.
  JobsController.instance.start();
  runApp(const QuarkApp());
}

/// The app's root messenger, so a snack bar raised outside any page — a job
/// finishing — shows on whatever page is open.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

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
