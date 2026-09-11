import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/trash_item.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';

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
}
