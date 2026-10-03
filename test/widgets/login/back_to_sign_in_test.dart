import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/recover_page.dart';
import 'package:quark/pages/request_account_page.dart';
import 'package:quark/pages/setup_page.dart';
import 'package:quark/pages/terms_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/widgets/login/back_to_sign_in.dart';

/// #2067: setup, recovery, requesting an account and the terms gate are each
/// alone on the navigator, so Android's Back closed the app from all of them.
void main() {
  final settings = AppSettings.instance;

  /// Whether the app asked Android to close it.
  var exited = false;

  setUp(() async {
    exited = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exited = true;
          return null;
        });
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://localhost:8095'),
    );
    authStatusProbe = () async => const AuthStatus(setupComplete: false);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    authStatusProbe = AuthService.checkStatus;
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  /// [page] at [location] the way the app reaches it, with `go`, so it is the
  /// only page on the navigator.
  Future<GoRouter> pumpAlone(
    WidgetTester tester,
    String location,
    Widget page,
  ) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: location, builder: (_, _) => page),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => const Scaffold(body: Text('settings')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  /// Android's system Back.
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  for (final (location, page) in [
    (AppRoutes.setup, SetupPage(onSetupComplete: () {})),
    (AppRoutes.recover, const RecoverPage()),
    (AppRoutes.requestAccount, const RequestAccountPage()),
  ]) {
    testWidgets('Back on $location goes to sign-in', (tester) async {
      await pumpAlone(tester, location, page);

      await pressBack(tester);

      expect(exited, isFalse);
      expect(find.text('login'), findsOneWidget);
    });
  }

  testWidgets('Back on a step that must be finished stays put', (tester) async {
    await pumpAlone(
      tester,
      AppRoutes.setup,
      const BackToSignIn(
        enabled: false,
        child: Scaffold(body: Text('recovery phrase')),
      ),
    );

    await pressBack(tester);

    expect(exited, isFalse);
    expect(find.text('recovery phrase'), findsOneWidget);
  });

  testWidgets('Back on the terms gate stays on the terms', (tester) async {
    await pumpAlone(tester, AppRoutes.terms, const TermsPage());

    await pressBack(tester);

    expect(exited, isFalse);
    expect(find.byType(TermsPage), findsOneWidget);
  });

  testWidgets('Back on terms opened from Settings returns to Settings', (
    tester,
  ) async {
    final router = await pumpAlone(tester, AppRoutes.terms, const TermsPage());
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    unawaited(router.push(AppRoutes.terms));
    await tester.pumpAndSettle();

    await pressBack(tester);

    expect(exited, isFalse);
    expect(find.byType(TermsPage), findsNothing);
    expect(find.text('settings'), findsOneWidget);
  });
}
