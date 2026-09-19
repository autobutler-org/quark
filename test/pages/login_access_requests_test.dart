import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// #1908: the sign-in form offers to request an account when the Quark takes
/// requests, and a sign-in refused for the account's status says so rather
/// than "invalid username or password".
void main() {
  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    await clearHosts();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://quark.local'),
    );
    await settings.acceptTerms();
  });

  tearDown(() async {
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
    authHttpClientFactory = () => sharedHttpClient;
  });

  Future<void> pumpLogin(WidgetTester tester) async {
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
          builder: (context, _) => LoginPage(
            onLoginSuccess: () => context.go(AppRoutes.files),
            // The same stub the gate asks, so both see one Quark.
            checkStatus: () => authStatusProbe(),
          ),
        ),
        GoRoute(
          path: AppRoutes.requestAccount,
          builder: (_, _) => const Scaffold(body: Text('request account')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('offers to request an account when the Quark takes requests', (
    tester,
  ) async {
    authStatusProbe = () async =>
        const AuthStatus(setupComplete: true, accessRequestsEnabled: true);

    await pumpLogin(tester);
    await tester.tap(find.byKey(const ValueKey('sign_in_request_access')));
    await tester.pumpAndSettle();

    expect(find.text('request account'), findsOneWidget);
  });

  testWidgets('offers nothing when requests are off', (tester) async {
    authStatusProbe = () async => const AuthStatus(setupComplete: true);

    await pumpLogin(tester);

    expect(find.byKey(const ValueKey('sign_in_request_access')), findsNothing);
  });

  testWidgets('offers nothing when the Quark cannot say', (tester) async {
    authStatusProbe = () async => throw Exception('connection refused');

    await pumpLogin(tester);

    expect(find.byKey(const ValueKey('sign_in_request_access')), findsNothing);
  });

  for (final (status, sentence) in [
    ('pending', Errors.accountPending),
    ('disabled', Errors.accountDisabled),
  ]) {
    testWidgets('a $status account signing in is told why', (tester) async {
      authStatusProbe = () async => const AuthStatus(setupComplete: true);
      authHttpClientFactory = () => MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'refused', 'status': status}),
          403,
        ),
      );

      await pumpLogin(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'bob',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'hunter2hunter2',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text(sentence), findsOneWidget);
      expect(settings.sessionToken, isNull);
    });
  }
}
