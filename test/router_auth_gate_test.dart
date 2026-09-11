import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/terms_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';

/// #1624: accepting terms navigated to /files and left it to [authRedirect] to
/// move the user on to login. That redirect swallowed every failure of the
/// status call and returned "stay put", so a transient connection failure at
/// exactly that moment stranded a signed-out user on a file browser that could
/// only render errors.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    // The session token lives in secure storage on native platforms, and
    // there's no plugin behind it in a unit test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
  });

  tearDown(() async {
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
  });

  /// Acceptance is recorded per host address and the singleton keeps that set
  /// for the whole run, so every test needs a Quark it has never seen.
  var hostSerial = 0;
  Future<void> addUnacceptedHost() async {
    hostSerial++;
    await settings.addHost(
      HostEntry(
        name: 'Quark $hostSerial',
        hostAddress: 'https://quark-$hostSerial.local',
      ),
    );
  }

  /// The real gate over stub pages, so the test drives the actual rules
  /// without mounting the whole app.
  Future<GoRouter> pumpGatedRouter(
    WidgetTester tester, {
    String initialLocation = AppRoutes.files,
  }) async {
    final router = GoRouter(
      initialLocation: initialLocation,
      redirect: authRedirect,
      refreshListenable: routerRefreshListenable,
      routes: [
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => const Scaffold(body: Text('files')),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
        GoRoute(
          path: AppRoutes.setup,
          builder: (_, _) => const Scaffold(body: Text('setup')),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => const Scaffold(body: Text('settings')),
        ),
        GoRoute(path: AppRoutes.terms, builder: (_, _) => const TermsPage()),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  group('accepting terms lands on', () {
    setUp(addUnacceptedHost);

    testWidgets('login, when the Quark is set up and reachable', (
      tester,
    ) async {
      authStatusProbe = () async => const AuthStatus(setupComplete: true);

      await pumpGatedRouter(tester);
      expect(find.text('I Agree'), findsOneWidget);

      await tester.tap(find.text('I Agree'));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('files'), findsNothing);
    });

    // The reported failure. On main this landed on 'files': the terms page
    // went there and the redirect's catch returned null.
    testWidgets('login, even when the status call fails at that moment', (
      tester,
    ) async {
      authStatusProbe = () async => throw Exception('connection refused');

      await pumpGatedRouter(tester);
      await tester.tap(find.text('I Agree'));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('files'), findsNothing);
    });

    testWidgets('setup, for a Quark nobody has claimed yet', (tester) async {
      authStatusProbe = () async => const AuthStatus(setupComplete: false);

      await pumpGatedRouter(tester);
      await tester.tap(find.text('I Agree'));
      await tester.pumpAndSettle();

      expect(find.text('setup'), findsOneWidget);
    });

    testWidgets('files, when a session already exists', (tester) async {
      await settings.setSessionToken('a-token');
      addTearDown(() => settings.setSessionToken(null));
      authStatusProbe = () async =>
          throw StateError('must not probe with a live session');

      await pumpGatedRouter(tester);
      await tester.tap(find.text('I Agree'));
      await tester.pumpAndSettle();

      expect(find.text('files'), findsOneWidget);
    });
  });

  group('an unreachable Quark does not strand a signed-out user', () {
    setUp(() async {
      await addUnacceptedHost();
      await settings.acceptTerms();
      authStatusProbe = () async => throw Exception('connection refused');
    });

    testWidgets('/files redirects to login rather than rendering errors', (
      tester,
    ) async {
      await pumpGatedRouter(tester);

      expect(find.text('login'), findsOneWidget);
      expect(find.text('files'), findsNothing);
    });

    // Settings is not the escape hatch any more: the login page owns host
    // management, so a bad address is corrected there (#1639). Settings stays
    // behind the auth gate like every other route.
    testWidgets('settings still redirects to login, not around the gate', (
      tester,
    ) async {
      final router = await pumpGatedRouter(tester);
      expect(find.text('login'), findsOneWidget);

      router.push(AppRoutes.settings);
      await tester.pumpAndSettle();

      expect(find.text('settings'), findsNothing);
      expect(find.text('login'), findsOneWidget);
    });
  });

  // #1645: the stored token was restored on launch but never consulted, because
  // /login sat in publicRoutes and returned null unconditionally.
  group('a stored session survives a restart', () {
    setUp(() async {
      await addUnacceptedHost();
      await settings.acceptTerms();
    });

    testWidgets('landing on login with a token goes straight to files', (
      tester,
    ) async {
      await settings.setSessionToken('a-token');
      addTearDown(() => settings.setSessionToken(null));
      authStatusProbe = () async =>
          throw StateError('must not probe with a live session');

      await pumpGatedRouter(tester, initialLocation: AppRoutes.login);

      expect(find.text('files'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });

    testWidgets('without a token the login page still shows', (tester) async {
      authStatusProbe = () async => const AuthStatus(setupComplete: true);

      await pumpGatedRouter(tester, initialLocation: AppRoutes.login);

      expect(find.text('login'), findsOneWidget);
    });

    // The self-heal the optimistic skip relies on: a 401 clears the token,
    // which fires the refresh listenable and re-runs the gate.
    testWidgets('a token cleared by a 401 lands back on login', (tester) async {
      await settings.setSessionToken('a-stale-token');
      addTearDown(() => settings.setSessionToken(null));
      authStatusProbe = () async => const AuthStatus(setupComplete: true);

      await pumpGatedRouter(tester, initialLocation: AppRoutes.login);
      expect(find.text('files'), findsOneWidget);

      await settings.setSessionToken(null);
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('files'), findsNothing);
    });
  });

  // The reported bug: signed into one Quark, switch to another you have never
  // signed into. Against a reachable Quark the 401 sorted it out; an
  // unreachable one never answers, so the old host's token stood and every
  // page rendered failures instead of the gate sending the user to login.
  group('switching to a Quark you are not signed into', () {
    late HostEntry signedIn;

    setUp(() async {
      await addUnacceptedHost();
      await settings.acceptTerms();
      signedIn = settings.hosts.single;
      await settings.setSessionToken('a-token');
      // The second Quark: terms accepted so the terms gate is not what fires,
      // and no session, because the user has never signed into it.
      await addUnacceptedHost();
      await settings.acceptTerms();
    });

    tearDown(() => settings.setSessionToken(null));

    testWidgets('lands on login even when that Quark is unreachable', (
      tester,
    ) async {
      authStatusProbe = () async => throw Exception('connection refused');

      // Back to the signed-in Quark to start, as the user was.
      await settings.setActiveIndex(0);
      await pumpGatedRouter(tester);
      expect(find.text('files'), findsOneWidget);

      await settings.setActiveIndex(1);
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('files'), findsNothing);
    });

    testWidgets('switching back restores the session on the first Quark', (
      tester,
    ) async {
      authStatusProbe = () async => throw Exception('connection refused');

      await settings.setActiveIndex(1);
      await pumpGatedRouter(tester);
      expect(find.text('login'), findsOneWidget);

      await settings.setActiveIndex(0);
      await tester.pumpAndSettle();

      expect(find.text('files'), findsOneWidget);
      expect(settings.sessionTokenFor(signedIn.hostAddress), 'a-token');
    });
  });

  // #1827: a Quark with no accounts yet stranded the user on /login. The
  // setup-vs-login decision only ran for a signed-out user landing on a
  // protected route, because /login sat in publicRoutes and returned null,
  // so the sign-in form could only ever answer "invalid credentials".
  group('a Quark nobody has claimed yet', () {
    setUp(() async {
      await addUnacceptedHost();
      await settings.acceptTerms();
    });

    // The reported bug.
    testWidgets('sends a user landing on login to setup', (tester) async {
      authStatusProbe = () async => const AuthStatus(setupComplete: false);

      await pumpGatedRouter(tester, initialLocation: AppRoutes.login);

      expect(find.text('setup'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });

    testWidgets('a set-up Quark leaves the user on login, with no loop', (
      tester,
    ) async {
      authStatusProbe = () async => const AuthStatus(setupComplete: true);

      await pumpGatedRouter(tester, initialLocation: AppRoutes.login);

      expect(find.text('login'), findsOneWidget);
      expect(find.text('setup'), findsNothing);
    });

    // The probe is best-effort. When it cannot answer, login is still the
    // right screen — the sign-in form's manual "set up this Quark" link is
    // what covers this case, not a redirect.
    testWidgets('a failed probe leaves the user on login', (tester) async {
      authStatusProbe = () async => throw Exception('connection refused');

      await pumpGatedRouter(tester, initialLocation: AppRoutes.login);

      expect(find.text('login'), findsOneWidget);
      expect(find.text('setup'), findsNothing);
    });

    // The repro from the report: sitting on /login, pick an unclaimed Quark.
    // Host selection only calls setState, so the redirect is what has to
    // notice — activeHostNotifier is in routerRefreshListenable.
    testWidgets('switching to it from login goes to setup', (tester) async {
      var setupComplete = true;
      authStatusProbe = () async => AuthStatus(setupComplete: setupComplete);

      // A second Quark, terms accepted, that turns out to have no accounts.
      await addUnacceptedHost();
      await settings.acceptTerms();
      await settings.setActiveIndex(0);

      await pumpGatedRouter(tester, initialLocation: AppRoutes.login);
      expect(find.text('login'), findsOneWidget);

      setupComplete = false;
      await settings.setActiveIndex(1);
      await tester.pumpAndSettle();

      expect(find.text('setup'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });
  });

  // The terms gate runs ahead of everything, so an unaccepted Quark sees terms
  // rather than the login page it would otherwise be sent to.
  testWidgets('settings still requires terms for the active Quark', (
    tester,
  ) async {
    await addUnacceptedHost();
    authStatusProbe = () async => const AuthStatus(setupComplete: true);

    await pumpGatedRouter(tester, initialLocation: AppRoutes.settings);

    expect(find.text('I Agree'), findsOneWidget);
    expect(find.text('settings'), findsNothing);
  });
}
