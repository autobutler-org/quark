import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/widgets/setup/recovery_phrase_step.dart';

import '../support/auth_salt.dart';

/// #1873: the first sign-in of an account an admin created returns its
/// recovery phrase, once. The router sends a token-holding user from /login to
/// /files, so storing the token before the phrase is acknowledged would tear
/// the phrase step down and lose the phrase for good.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final stored = <String, String>{};

  setUpAll(() async {
    // Loaded once outside the fake clock, so a sign-in can derive keys.
    await ChatCrypto.load();
    chatKeysOnSignIn =
        ({
          required password,
          recoveryPhrase,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
          final key = call.arguments['key'] as String?;
          switch (call.method) {
            case 'read':
              return stored[key];
            case 'write':
              stored[key!] = call.arguments['value'] as String;
              return null;
            case 'delete':
              stored.remove(key);
              return null;
            default:
              return null;
          }
        });
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
    stored.clear();
    await clearHosts();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://quark.local'),
    );
    await settings.acceptTerms();
    authStatusProbe = () async => const AuthStatus(setupComplete: true);
  });

  tearDown(() async {
    await settings.setSessionToken(null);
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
    authHttpClientFactory = () => sharedHttpClient;
  });

  /// Signs in against a Quark that answers the sign-in with [loginBody].
  /// With [rotation], it has a salt endpoint and answers
  /// `PUT /auth/recovery-key` with that status; without, it is a Quark from
  /// before #2430.
  Future<void> pumpLoginAndSignIn(
    WidgetTester tester,
    Map<String, Object?> loginBody, {
    int? rotation,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    authHttpClientFactory = () => AuthSaltClient(
      MockClient(
        (request) async => request.url.path == '/api/v0/auth/recovery-key'
            ? http.Response('', rotation!)
            : http.Response(jsonEncode(loginBody), 200),
      ),
      status: rotation == null ? 404 : 200,
    );

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
          builder: (context, _) => LoginPage(
            onLoginSuccess: () => context.go(AppRoutes.files),
            checkStatus: () => authStatusProbe(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'bob',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter2hunter2',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    // Deriving keys needs the real event loop as well as the fake clock.
    for (var i = 0; rotation != null && i < 20; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('holds the session until the phrase is acknowledged', (
    tester,
  ) async {
    await pumpLoginAndSignIn(tester, {
      'token': 'first-token',
      'recoveryPhrase': 'apple banana cherry',
    });

    // The phrase is on screen, and nothing is stored yet, so the router has
    // no reason to leave the login page.
    expect(find.byType(RecoveryPhraseStep), findsOneWidget);
    expect(settings.sessionToken, isNull);
    expect(find.text('files'), findsNothing);

    // Continue does nothing until the box is checked.
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(settings.sessionToken, isNull);
    expect(find.byType(RecoveryPhraseStep), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(settings.sessionToken, 'first-token');
    expect(settings.username, 'bob');
    expect(find.text('files'), findsOneWidget);
  });

  testWidgets('an ordinary sign-in stores the session straight away', (
    tester,
  ) async {
    await pumpLoginAndSignIn(tester, {'token': 'plain-token'});

    expect(find.byType(RecoveryPhraseStep), findsNothing);
    expect(settings.sessionToken, 'plain-token');
    expect(find.text('files'), findsOneWidget);
  });

  group('a phrase the Quark made is replaced (#2430):', () {
    const serverPhrase = 'server-made-phrase';

    testWidgets('the new one is shown once the Quark has taken it, and the '
        "Quark's never is", (tester) async {
      await pumpLoginAndSignIn(tester, {
        'token': 'first-token',
        'recoveryPhrase': serverPhrase,
        'legacyRecovery': true,
      }, rotation: 204);

      final step = tester.widget<RecoveryPhraseStep>(
        find.byType(RecoveryPhraseStep),
      );
      expect(step.phrase.split('-'), hasLength(6));
      expect(step.phrase, isNot(serverPhrase));
      expect(find.textContaining(serverPhrase), findsNothing);
      expect(settings.sessionToken, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(settings.sessionToken, 'first-token');
      expect(find.text('files'), findsOneWidget);
    });

    for (final serverMade in [true, false]) {
      testWidgets('a rotation the Quark refused shows nothing and signs in'
          '${serverMade ? ', even on a first sign-in' : ''}', (tester) async {
        await pumpLoginAndSignIn(tester, {
          'token': 'plain-token',
          if (serverMade) 'recoveryPhrase': serverPhrase,
          'legacyRecovery': true,
        }, rotation: 403);

        expect(find.byType(RecoveryPhraseStep), findsNothing);
        expect(settings.sessionToken, 'plain-token');
        expect(find.text('files'), findsOneWidget);
      });
    }
  });
}
