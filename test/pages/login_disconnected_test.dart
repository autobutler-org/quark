import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';

import '../support/tap_target_guidelines.dart' show setViewport;
import '../support/unreachable_quark.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #1637: signing in to a Quark the app cannot reach used to render the raw
/// connection failure in the credentials banner — which reads as "wrong
/// password" for what is really "you are on the wrong network".
///
/// The login page is the one route reachable with an unreachable Quark
/// configured (#1639), so this is where the explanation matters most.
void main() {
  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  late HttpOverrides? priorOverrides;

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await clearHosts();
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await clearHosts();
  });

  /// Stands in for a Quark left behind on the home network. Nothing actually
  /// dials it — [UnreachableQuarkHttpOverrides] refuses every connection.
  const unreachableAddress = 'https://quark.local';

  Future<void> pumpLogin(WidgetTester tester) async {
    setViewport(tester, const Size(1200, 2400));

    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: unreachableAddress),
    );
    await settings.acceptTerms();

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
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, 'someone');
    await tester.enterText(find.byType(TextFormField).last, 'a-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sign-in that never reaches the Quark says so plainly', (
    tester,
  ) async {
    await pumpLogin(tester);
    await signIn(tester);

    expect(find.byType(QuarkDisconnectedBanner), findsOneWidget);
    expect(find.text(quarkDisconnectedHeadline), findsOneWidget);
    expect(find.text(quarkDisconnectedBody), findsOneWidget);
  });

  testWidgets('it offers the troubleshooting steps, not an exception', (
    tester,
  ) async {
    await pumpLogin(tester);
    await signIn(tester);

    for (final step in quarkTroubleshootingStepsInPlace) {
      expect(find.text(step), findsOneWidget);
    }
    // The exact leakage from the bug report: exception type names, OS errno,
    // and the full request URI, rendered in the page.
    expect(find.textContaining('ClientException'), findsNothing);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('errno'), findsNothing);
    expect(find.textContaining(unreachableAddress), findsOneWidget);
  });

  testWidgets('the user can still switch Quarks from the failed state', (
    tester,
  ) async {
    await pumpLogin(tester);
    await signIn(tester);

    // The banner must not have displaced the escape hatch (#1639).
    expect(find.text('Change'), findsOneWidget);
  });
}
