import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/trash_item.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/pages/recover_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';

void main() {
  group('AppRoutes.encodeFilePath', () {
    test('leaves an ordinary path untouched', () {
      expect(
        AppRoutes.encodeFilePath('photos/2024/beach.jpg'),
        'photos/2024/beach.jpg',
      );
    });

    test('strips leading slashes', () {
      expect(AppRoutes.encodeFilePath('/photos/beach.jpg'), 'photos/beach.jpg');
    });

    test('encodes spaces but keeps the separators', () {
      expect(
        AppRoutes.encodeFilePath('my folder/my doc.qdoc'),
        'my%20folder/my%20doc.qdoc',
      );
    });

    test('encodes a literal percent so it survives one decode', () {
      expect(
        AppRoutes.encodeFilePath('holiday 100%.qdoc'),
        'holiday%20100%25.qdoc',
      );
    });

    test('is empty for the root', () {
      expect(AppRoutes.encodeFilePath('/'), '');
      expect(AppRoutes.encodeFilePath(''), '');
    });
  });

  group('route builders emit URLs go_router can echo back verbatim', () {
    // #1604: these were built by raw interpolation, so a name with a space
    // produced '/files/my doc.qdoc' while the live location read
    // '/files/my%20doc.qdoc'. Every site comparing the two mismatched.
    for (final name in const [
      'plain.qdoc',
      'my doc.qdoc',
      'holiday 100%.qdoc',
      'a+b.qdoc',
      'note#1.qdoc',
    ]) {
      test('filesPath round-trips [$name]', () {
        final built = AppRoutes.filesPath('/folder/$name');
        expect(
          Uri.parse(built).toString(),
          built,
          reason: 'built route must already be in canonical URL form',
        );
      });
    }

    test('docFile, sheetFile and plaintextEditorPath encode too', () {
      expect(AppRoutes.docFile('/my doc.qdoc'), '/docs/my%20doc.qdoc');
      expect(
        AppRoutes.sheetFile('/my sheet.qsheet'),
        '/sheets/my%20sheet.qsheet',
      );
      expect(
        AppRoutes.plaintextEditorPath('/my notes.txt'),
        '/edit/my%20notes.txt',
      );
    });
  });

  group('AppRoutes.canonicalRoute', () {
    test('makes an unencoded route compare equal to the live location', () {
      expect(
        AppRoutes.canonicalRoute('/files/my doc.qdoc'),
        AppRoutes.canonicalRoute('/files/my%20doc.qdoc'),
      );
    });

    test('returns the input unchanged when it will not parse', () {
      expect(AppRoutes.canonicalRoute('http://[::bad'), 'http://[::bad');
    });
  });

  group('/files/:path delivers the real path to FileBrowserPage', () {
    Future<String?> pathSeenFor(WidgetTester tester, String location) async {
      String? seen;
      final router = GoRouter(
        initialLocation: '/files',
        routes: [
          GoRoute(
            path: AppRoutes.files,
            builder: (_, _) => const Scaffold(body: Text('root')),
            routes: [
              GoRoute(
                path: ':path(.*)',
                builder: (_, state) {
                  // Mirrors the real builder: go_router already decodes.
                  seen = state.pathParameters['path'];
                  return Scaffold(body: Text('leaf:$seen'));
                },
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go(location);
      await tester.pumpAndSettle();
      return seen;
    }

    testWidgets('a name with a space arrives decoded exactly once', (
      tester,
    ) async {
      final seen = await pathSeenFor(
        tester,
        AppRoutes.filesPath('/my doc.qdoc'),
      );
      expect(seen, '/my doc.qdoc');
    });

    // Decoding a second time threw FormatException on any name with a '%'.
    testWidgets('a name with a percent sign does not throw', (tester) async {
      final seen = await pathSeenFor(
        tester,
        AppRoutes.filesPath('/holiday 100%.qdoc'),
      );
      expect(seen, '/holiday 100%.qdoc');
    });

    testWidgets('a literal %20 in a name is preserved', (tester) async {
      final seen = await pathSeenFor(
        tester,
        AppRoutes.filesPath('/odd%20name.qdoc'),
      );
      expect(seen, '/odd%20name.qdoc');
    });
  });

  group('/trash/:path addresses a folder in the trash', () {
    test('the root is /trash', () {
      expect(AppRoutes.trashFolder(null), '/trash');
      expect(AppRoutes.parseTrashFolder('', ''), isNull);
    });

    test('builds an encoded URL with the serial as a query param', () {
      expect(
        AppRoutes.trashFolder((
          serial: 'USB 1',
          trashName: '20260901T000000Z_ab_my album',
          path: '2024/day one',
        )),
        '/trash/20260901T000000Z_ab_my%20album/2024/day%20one?serial=USB+1',
      );
      expect(
        AppRoutes.trashFolder((serial: '', trashName: 'x_album', path: '')),
        '/trash/x_album',
      );
    });

    testWidgets('a built URL routes back to the same location', (tester) async {
      const location = (
        serial: 'USB1',
        trashName: 'x_holiday 100%',
        path: 'odd%20name/sub',
      );
      TrashLocation? seen;
      final router = GoRouter(
        initialLocation: AppRoutes.trash,
        routes: [
          GoRoute(
            path: AppRoutes.trash,
            builder: (_, _) => const Scaffold(body: Text('root')),
            routes: [
              GoRoute(
                path: ':path(.*)',
                builder: (_, state) {
                  // Mirrors the real builder.
                  seen = AppRoutes.parseTrashFolder(
                    state.pathParameters['path'] ?? '',
                    state.uri.queryParameters['serial'] ?? '',
                  );
                  return const Scaffold(body: Text('folder'));
                },
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go(AppRoutes.trashFolder(location));
      await tester.pumpAndSettle();

      expect(seen, location);
    });
  });

  group('AppRoutes.photosAlbum', () {
    test('names the album in the query, and is /photos for All photos', () {
      expect(AppRoutes.photosAlbum('3'), '/photos?album=3');
      expect(AppRoutes.photosAlbum('-2'), '/photos?album=-2');
      expect(AppRoutes.photosAlbum('Trips'), '/photos?album=Trips');
      expect(AppRoutes.photosAlbum(null), AppRoutes.photos);
      expect(AppRoutes.photosAlbum(''), AppRoutes.photos);
    });

    test('keeps slashes readable and encodes everything else', () {
      expect(
        AppRoutes.photosAlbum('Summer Trip/Japan'),
        '/photos?album=Summer%20Trip/Japan',
      );
      for (final name in ['A & B', 'C+D', '100%', 'x=1#y', 'Trips/Å']) {
        expect(
          Uri.parse(AppRoutes.photosAlbum(name)).queryParameters['album'],
          name,
          reason: name,
        );
      }
    });
  });

  // #1623: the terms gate only re-ran when `refreshListenable` fired, and
  // `activeHost` wasn't in that list. Connecting to a Quark for the first time
  // therefore left the user on the file browser until some later navigation
  // happened to re-run the redirect.
  group('the terms gate reacts to connecting a host', () {
    final settings = AppSettings.instance;

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

    Future<void> reset() async {
      while (settings.hosts.isNotEmpty) {
        await settings.removeHost(settings.hosts.length - 1);
      }
      await settings.setSessionToken(null);
    }

    setUp(reset);
    tearDown(reset);

    /// The real redirect and the real refresh listenable, over stub pages so
    /// the test doesn't mount the whole app.
    Future<GoRouter> pumpGatedRouter(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.files,
        redirect: authRedirect,
        refreshListenable: routerRefreshListenable,
        routes: [
          GoRoute(
            path: AppRoutes.files,
            builder: (_, _) => const Scaffold(body: Text('files')),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, _) => const Scaffold(body: Text('settings')),
          ),
          GoRoute(
            path: AppRoutes.login,
            builder: (_, _) => const Scaffold(body: Text('login')),
          ),
          GoRoute(
            path: AppRoutes.terms,
            builder: (_, _) => const Scaffold(body: Text('terms')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    // #1639: with no Quark configured there is nothing any other route can
    // do, and Settings — where hosts used to be managed — is behind the gate.
    // Login owns host management now, so that is where the user lands.
    testWidgets('no host configured sends the user to login', (tester) async {
      await pumpGatedRouter(tester);

      expect(find.text('login'), findsOneWidget);
      expect(find.text('files'), findsNothing);
    });

    testWidgets('a deep link with no host configured still lands on login', (
      tester,
    ) async {
      final router = await pumpGatedRouter(tester);

      router.go(AppRoutes.settings);
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('settings'), findsNothing);
    });

    // Connecting a Quark must show terms straight away even though the user is
    // sitting on a public route (#1631) — the terms gate runs ahead of the
    // public-route allowance for exactly this.
    testWidgets('adding the first host shows terms without any navigation', (
      tester,
    ) async {
      await pumpGatedRouter(tester);
      expect(find.text('login'), findsOneWidget);

      await settings.addHost(
        HostEntry(name: 'My Quark', hostAddress: 'http://quark.local'),
      );
      await tester.pumpAndSettle();

      expect(find.text('terms'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });

    // The reported repro: terms already accepted for the Quark you're on,
    // then you retype the backend URL in Settings. That points the app at a
    // Quark you've never accepted terms for, so the gate must fire again.
    testWidgets('retyping the backend URL sends an accepted user to terms', (
      tester,
    ) async {
      await settings.addHost(
        HostEntry(name: 'Mine', hostAddress: 'http://accepted.local'),
      );
      await settings.acceptTerms();
      // Signed in, because that is who is sitting in Settings retyping the
      // address. A signed-out user is sent to login instead (#1624).
      await settings.setSessionToken('test-session');

      final router = await pumpGatedRouter(tester);
      router.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(find.text('settings'), findsOneWidget);

      await settings.updateHost(
        0,
        HostEntry(name: 'Mine', hostAddress: 'http://never-seen.local'),
      );
      await tester.pumpAndSettle();

      expect(find.text('terms'), findsOneWidget);
    });

    testWidgets('switching to another host re-runs the gate', (tester) async {
      await settings.addHost(
        HostEntry(name: 'One', hostAddress: 'http://one.local'),
      );
      await settings.addHost(
        HostEntry(name: 'Two', hostAddress: 'http://two.local'),
      );

      final router = await pumpGatedRouter(tester);
      expect(find.text('terms'), findsOneWidget);

      // Force the browser back up, then switch hosts: the gate must catch it.
      router.go(AppRoutes.files);
      await tester.pumpAndSettle();

      await settings.setActiveIndex(0);
      await tester.pumpAndSettle();

      expect(find.text('terms'), findsOneWidget);
    });
  });

  // #2063: browser Back did nothing on Forgot password, and /forgot-password
  // typed as a URL was Page not found.
  group('browser history', () {
    final settings = AppSettings.instance;

    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );

    /// The browser's history stack, built from what the router reports to
    /// the engine: on web each report is a pushState, or a replaceState when
    /// it says `replace`.
    final history = <String>[];

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, (_) async => null);
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, null);
    });

    Future<void> reset() async {
      while (settings.hosts.isNotEmpty) {
        await settings.removeHost(settings.hosts.length - 1);
      }
      await settings.setSessionToken(null);
      authStatusProbe = AuthService.checkStatus;
    }

    setUp(() async {
      await reset();
      history.clear();
      await settings.addHost(
        HostEntry(name: 'Home', hostAddress: 'http://history.local'),
      );
      await settings.acceptTerms();
      authStatusProbe = () async => const AuthStatus(setupComplete: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
            if (call.method != 'routeInformationUpdated') return null;
            final args = call.arguments as Map;
            final uri = (args['uri'] ?? args['location']).toString();
            if (args['replace'] == true && history.isNotEmpty) {
              history.last = uri;
            } else {
              history.add(uri);
            }
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.navigation, null);
      await reset();
    });

    /// Browser Back: the browser drops its current entry and the engine
    /// hands the framework the one before it.
    Future<void> browserBack(WidgetTester tester) async {
      history.removeLast();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('pushRouteInformation', {
            'location': history.last,
            'state': null,
          }),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    /// The app's real routes and gate.
    Future<GoRouter> pumpRealRoutes(
      WidgetTester tester,
      String initialLocation,
    ) async {
      final testRouter = GoRouter(
        initialLocation: initialLocation,
        redirect: authRedirect,
        refreshListenable: routerRefreshListenable,
        routes: router.configuration.routes,
      );
      addTearDown(testRouter.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();
      return testRouter;
    }

    String location(GoRouter r) =>
        r.routeInformationProvider.value.uri.toString();

    testWidgets('/forgot-password opens recovery with the username kept', (
      tester,
    ) async {
      final r = await pumpRealRoutes(tester, '/forgot-password?username=ada');

      expect(find.byType(RecoverPage), findsOneWidget);
      expect(location(r), '/recover?username=ada');
      expect(find.text('ada'), findsOneWidget);
    });

    testWidgets('Forgot password is a history entry browser Back leaves', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final r = GoRouter(
        initialLocation: AppRoutes.login,
        redirect: authRedirect,
        refreshListenable: routerRefreshListenable,
        routes: [
          GoRoute(
            path: AppRoutes.login,
            builder: (context, _) => LoginPage(
              onLoginSuccess: () {},
              checkStatus: () => authStatusProbe(),
            ),
          ),
          GoRoute(
            path: AppRoutes.recover,
            builder: (_, state) => RecoverPage(
              initialUsername: state.uri.queryParameters['username'],
            ),
          ),
        ],
      );
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'ada');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.byType(RecoverPage), findsOneWidget);
      expect(location(r), '/recover?username=ada');
      expect(history.last, '/recover?username=ada');

      await browserBack(tester);

      expect(find.byType(RecoverPage), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(location(r), AppRoutes.login);
    });

    testWidgets('the recover page offers its own way back to sign in', (
      tester,
    ) async {
      final r = await pumpRealRoutes(tester, AppRoutes.recover);

      final back = find.byKey(const ValueKey('recover_back'));
      await tester.ensureVisible(back);
      await tester.tap(back);
      await tester.pumpAndSettle();

      expect(location(r), AppRoutes.login);
    });

    testWidgets('browser Back from Settings returns to Files', (tester) async {
      await settings.setSessionToken('a-token');
      final r = GoRouter(
        initialLocation: AppRoutes.files,
        redirect: authRedirect,
        refreshListenable: routerRefreshListenable,
        routes: [
          GoRoute(
            path: AppRoutes.files,
            builder: (_, _) => const Scaffold(body: Text('files')),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, _) => const Scaffold(body: Text('settings')),
          ),
        ],
      );
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();

      r.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(history, [AppRoutes.files, AppRoutes.settings]);

      await browserBack(tester);

      expect(find.text('files'), findsOneWidget);
      expect(location(r), AppRoutes.files);
    });

    // #2350: a tab switch is a history entry, so Back returns to the tab.
    testWidgets('browser Back from a Settings tab returns to the last tab', (
      tester,
    ) async {
      final r = GoRouter(
        initialLocation: AppRoutes.settings,
        routes: tabbedRoutes(
          path: AppRoutes.settings,
          tabs: SettingsTab.values,
          builder: (tab, onTabSelected) => Scaffold(
            body: TextButton(
              onPressed: () => onTabSelected(SettingsTab.account),
              child: Text('settings ${tab.slug}'),
            ),
          ),
        ),
      );
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();

      await tester.tap(find.text('settings general'));
      await tester.pumpAndSettle();
      expect(location(r), AppRoutes.settingsTab(SettingsTab.account));

      await browserBack(tester);

      expect(find.text('settings general'), findsOneWidget);
      expect(location(r), AppRoutes.settingsTab(SettingsTab.general));
    });
  });

  // #2349: a page whose tabs have their own URLs.
  group('tabbedRoutes', () {
    Future<GoRouter> pumpTabbed(WidgetTester tester, String location) async {
      final r = GoRouter(
        initialLocation: location,
        routes: tabbedRoutes(
          path: AppRoutes.users,
          tabs: UsersTab.values,
          builder: (tab, onTabSelected) =>
              _TabbedPage(tab: tab, onTabSelected: onTabSelected),
        ),
      );
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      return r;
    }

    String at(GoRouter r) =>
        r.routerDelegate.currentConfiguration.uri.toString();

    setUp(() => _TabbedPageState.created = 0);

    testWidgets('the base path redirects to the first tab', (tester) async {
      final r = await pumpTabbed(tester, AppRoutes.users);

      expect(at(r), AppRoutes.usersTab(UsersTab.accounts));
      expect(find.text('tab accounts'), findsOneWidget);
    });

    testWidgets('a tab URL opens on that tab', (tester) async {
      final r = await pumpTabbed(tester, AppRoutes.usersTab(UsersTab.groups));

      expect(at(r), '/users/groups');
      expect(find.text('tab groups'), findsOneWidget);
    });

    testWidgets('an unknown tab redirects to the first tab', (tester) async {
      final r = await pumpTabbed(tester, '/users/bogus');

      expect(at(r), '/users/accounts');
      expect(find.text('tab accounts'), findsOneWidget);
    });

    testWidgets('the query string survives the redirect', (tester) async {
      final base = await pumpTabbed(tester, '/users?serial=abc');
      expect(at(base), '/users/accounts?serial=abc');

      base.go('/users/bogus?serial=abc');
      await tester.pumpAndSettle();
      expect(at(base), '/users/accounts?serial=abc');
    });

    testWidgets('switching tabs keeps the same page State', (tester) async {
      final r = await pumpTabbed(tester, AppRoutes.users);
      final before = tester.state(find.byType(_TabbedPage));

      await tester.tap(find.byKey(const ValueKey('select_groups')));
      await tester.pumpAndSettle();

      expect(at(r), '/users/groups');
      expect(find.text('tab groups'), findsOneWidget);
      expect(tester.state(find.byType(_TabbedPage)), same(before));

      // The browser's back button lands as a go to the earlier URL.
      r.go(AppRoutes.usersTab(UsersTab.accounts));
      await tester.pumpAndSettle();

      expect(find.text('tab accounts'), findsOneWidget);
      expect(tester.state(find.byType(_TabbedPage)), same(before));
      expect(_TabbedPageState.created, 1);
    });
  });

  // #2351: Health, Devices and Jobs became tabs of the System page.
  group('the pages the System page took in', () {
    Future<GoRouter> pumpLegacy(WidgetTester tester, String location) async {
      const legacy = {AppRoutes.health, AppRoutes.devices, AppRoutes.jobs};
      final r = GoRouter(
        initialLocation: location,
        routes: [
          // The app's own redirects, under a stand-in for the page.
          ...router.configuration.routes.whereType<GoRoute>().where(
            (route) => legacy.contains(route.path),
          ),
          ...tabbedRoutes(
            path: AppRoutes.system,
            tabs: SystemTab.values,
            builder: (tab, _) => Text('system ${tab.slug}'),
          ),
        ],
      );
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      return r;
    }

    String at(GoRouter r) =>
        r.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('/system opens Health', (tester) async {
      final r = await pumpLegacy(tester, AppRoutes.system);

      expect(at(r), '/system/health');
      expect(find.text('system health'), findsOneWidget);
    });

    for (final (old, tab) in [
      ('/health', SystemTab.health),
      ('/devices', SystemTab.storage),
      ('/jobs', SystemTab.jobs),
    ]) {
      testWidgets('$old redirects to its tab with the query kept', (
        tester,
      ) async {
        final r = await pumpLegacy(tester, '$old?serial=abc');

        expect(at(r), '${AppRoutes.systemTab(tab)}?serial=abc');
        expect(find.text('system ${tab.slug}'), findsOneWidget);
      });
    }
  });

  // #2350: Settings' tabs each have a URL, and General comes first.
  group('Settings tabs', () {
    test('the app mounts every Settings tab under one route', () {
      final paths = router.configuration.routes.whereType<GoRoute>().map(
        (route) => route.path,
      );
      expect(paths, containsAll([AppRoutes.settings, '/settings/:tab']));
    });

    test('the app declares account and data before the Settings tabs', () {
      final paths = router.configuration.routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList();
      expect(
        paths.indexOf(AppRoutes.accountAndData),
        lessThan(paths.indexOf('/settings/:tab')),
      );
      expect(paths.indexOf(AppRoutes.accountAndData), isNot(-1));
    });

    test('are General, Account, Network, Updates and About, in order', () {
      expect(SettingsTab.values.map(AppRoutes.settingsTab), [
        '/settings/general',
        '/settings/account',
        '/settings/network',
        '/settings/updates',
        '/settings/about',
      ]);
    });

    Future<GoRouter> pumpSettings(WidgetTester tester, String location) async {
      final r = GoRouter(
        initialLocation: location,
        routes: tabbedRoutes(
          path: AppRoutes.settings,
          tabs: SettingsTab.values,
          builder: (tab, _) =>
              Text('settings ${tab.slug}', textDirection: TextDirection.ltr),
        ),
      );
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      return r;
    }

    String at(GoRouter r) =>
        r.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('/settings redirects to General', (tester) async {
      final r = await pumpSettings(tester, AppRoutes.settings);

      expect(at(r), '/settings/general');
      expect(find.text('settings general'), findsOneWidget);
    });

    for (final tab in SettingsTab.values) {
      testWidgets('/settings/${tab.slug} opens that tab', (tester) async {
        final r = await pumpSettings(tester, AppRoutes.settingsTab(tab));

        expect(at(r), '/settings/${tab.slug}');
        expect(find.text('settings ${tab.slug}'), findsOneWidget);
      });
    }

    testWidgets('an unknown tab lands on General', (tester) async {
      final r = await pumpSettings(tester, '/settings/storage');

      expect(at(r), '/settings/general');
      expect(find.text('settings general'), findsOneWidget);
    });

    // A page under Settings that is not a tab, such as #2346's account and
    // data drill-down. go_router takes the first route that matches.
    Future<GoRouter> pumpWithDrillDown(
      WidgetTester tester,
      String drillDown, {
      required bool before,
    }) async {
      final page = GoRoute(
        path: drillDown,
        builder: (_, _) =>
            const Text('drill-down', textDirection: TextDirection.ltr),
      );
      final tabs = tabbedRoutes(
        path: AppRoutes.settings,
        tabs: SettingsTab.values,
        builder: (tab, _) =>
            Text('settings ${tab.slug}', textDirection: TextDirection.ltr),
      );
      final r = GoRouter(
        initialLocation: drillDown,
        routes: before ? [page, ...tabs] : [...tabs, page],
      );
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      return r;
    }

    testWidgets('a sibling of the tabs resolves when declared before them', (
      tester,
    ) async {
      final r = await pumpWithDrillDown(
        tester,
        '/settings/account-and-data',
        before: true,
      );

      expect(at(r), '/settings/account-and-data');
      expect(find.text('drill-down'), findsOneWidget);
    });

    testWidgets('a sibling declared after the tabs is taken for a tab', (
      tester,
    ) async {
      final r = await pumpWithDrillDown(
        tester,
        '/settings/account-and-data',
        before: false,
      );

      expect(at(r), '/settings/general');
      expect(find.text('drill-down'), findsNothing);
    });

    testWidgets('a page under a tab resolves wherever it is declared', (
      tester,
    ) async {
      final r = await pumpWithDrillDown(
        tester,
        '/settings/account/data',
        before: false,
      );

      expect(at(r), '/settings/account/data');
      expect(find.text('drill-down'), findsOneWidget);
    });
  });
}

/// A tabbed page that counts how often its State is created: every creation
/// past the first is a tab switch that rebuilt the page and would refetch.
class _TabbedPage extends StatefulWidget {
  const _TabbedPage({required this.tab, required this.onTabSelected});

  final UsersTab tab;
  final ValueChanged<UsersTab> onTabSelected;

  @override
  State<_TabbedPage> createState() => _TabbedPageState();
}

class _TabbedPageState extends State<_TabbedPage> {
  static var created = 0;

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('tab ${widget.tab.slug}'),
        TextButton(
          key: const ValueKey('select_groups'),
          onPressed: () => widget.onTabSelected(UsersTab.groups),
          child: const Text('groups'),
        ),
      ],
    ),
  );
}
