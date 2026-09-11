import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/widgets/host_dialog.dart';
import 'package:quark/widgets/host_manager.dart';
import 'package:quark/widgets/quark_connect_form.dart';

/// #1639: pointing the app at a Quark you can't reach used to soft-lock the
/// user on this page — every other route, Settings included, is behind the
/// auth gate. The login page is the landing page now and owns host
/// management, so it must always offer a way out.
void main() {
  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    await clearHosts();
    // The gate probes on every /login render now (#1827). Stub it so these
    // tests exercise host management rather than a failing socket.
    authStatusProbe = () async => const AuthStatus(setupComplete: true);
  });
  tearDown(() async {
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
  });

  /// The real gate over stub pages, so the test exercises the redirects the
  /// app actually runs.
  Future<GoRouter> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: AppRoutes.login,
      redirect: authRedirect,
      refreshListenable: routerRefreshListenable,
      routes: [
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => const Scaffold(body: Text('files')),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, _) =>
              LoginPage(onLoginSuccess: () => context.go(AppRoutes.files)),
        ),
        GoRoute(
          path: AppRoutes.terms,
          builder: (_, _) => const Scaffold(body: Text('terms')),
        ),
        GoRoute(
          path: AppRoutes.setup,
          builder: (_, _) => const Scaffold(body: Text('setup')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  group('with no Quark configured', () {
    testWidgets('the login page offers the connect form, not a sign-in form', (
      tester,
    ) async {
      await pumpLogin(tester);

      expect(find.byType(QuarkConnectForm), findsOneWidget);
      expect(find.text('Connect to your Quark'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('connecting saves the host, normalizing a bare address', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tester.enterText(find.byType(TextField), 'my-quark.local');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // A quark serves TLS, so a schemeless address becomes https://.
      expect(settings.hosts.single.hostAddress, 'https://my-quark.local');
      expect(settings.activeHost, 'https://my-quark.local');
    });

    // The gate runs terms ahead of the public-route allowance (#1631), so
    // connecting from the login page shows terms straight away.
    testWidgets('connecting goes on to the terms page', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(find.byType(TextField), 'https://quark.local');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('terms'), findsOneWidget);
    });
  });

  group('with a Quark configured', () {
    Future<void> addAccepted(String name, String address) async {
      await settings.addHost(HostEntry(name: name, hostAddress: address));
      await settings.acceptTerms();
    }

    testWidgets('the sign-in form names the Quark it will sign in to', (
      tester,
    ) async {
      await addAccepted('Home', 'http://quark.local');
      await pumpLogin(tester);

      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('http://quark.local'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      // Collapsed until asked for.
      expect(find.byType(HostManager), findsNothing);
    });

    // #1827: the manual escape hatch to /setup. Always rendered, because the
    // gate's status probe can be slow, failed or offline — it must never be
    // the only way to reach the setup wizard.
    testWidgets('the sign-in form offers a way to set up an unclaimed Quark', (
      tester,
    ) async {
      await addAccepted('Home', 'http://quark.local');
      await pumpLogin(tester);

      expect(find.text('First time here? Set up this Quark'), findsOneWidget);
    });

    // It has to *navigate*, not push. go_router ships
    // optionURLReflectsImperativeAPIs = false, so an imperative push renders
    // the wizard while the address bar still reads /login — the match list's
    // own uri is what gets reported to the browser, and it is the only thing
    // here that tells `go` and `push` apart (the wizard shows either way).
    testWidgets('tapping it leaves login for the setup wizard', (tester) async {
      await addAccepted('Home', 'http://quark.local');
      final router = await pumpLogin(tester);

      await tester.tap(find.text('First time here? Set up this Quark'));
      await tester.pumpAndSettle();

      expect(find.text('setup'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.setup,
      );
    });

    testWidgets('Change reveals the host list and the add button', (
      tester,
    ) async {
      await addAccepted('Home', 'http://quark.local');
      await pumpLogin(tester);

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      expect(find.byType(HostManager), findsOneWidget);
      expect(find.text('Add Quark'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('a second Quark can be switched to without signing in', (
      tester,
    ) async {
      await addAccepted('Home', 'http://home.local');
      await addAccepted('Cabin', 'http://cabin.local');
      await settings.setActiveIndex(0);
      expect(settings.activeHost, 'http://home.local');

      await pumpLogin(tester);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('http://cabin.local'));
      await tester.pumpAndSettle();

      expect(settings.activeHost, 'http://cabin.local');
    });

    testWidgets('a new Quark can be added from the login page', (tester) async {
      await addAccepted('Home', 'http://home.local');
      await pumpLogin(tester);

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Quark'));
      await tester.pumpAndSettle();

      // Scoped to the dialog: the sign-in form behind it owns TextFields too.
      final dialogFields = find.descendant(
        of: find.byType(HostDialog),
        matching: find.byType(TextField),
      );
      expect(dialogFields, findsNWidgets(2));
      await tester.enterText(dialogFields.first, 'Cabin');
      await tester.enterText(dialogFields.last, 'http://cabin.local');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(settings.hosts.length, 2);
      expect(settings.hosts.last.hostAddress, 'http://cabin.local');
      expect(settings.activeHost, 'http://cabin.local');
    });
  });
}
