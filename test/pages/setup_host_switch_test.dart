import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:quark/pages/setup_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/login/host_switcher.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The setup page carries the login page's host switcher, and every Quark it
/// lands on is asked whether it has been claimed: a claimed one sends the user
/// to login, an unreachable one shows the disconnected banner.
void main() {
  final settings = AppSettings.instance;
  const fresh = 'http://localhost:8091';
  const claimed = 'http://localhost:8092';
  const dead = 'http://localhost:8093';

  setUp(() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    for (final (name, address) in [
      ('Fresh', fresh),
      ('Claimed', claimed),
      ('Dead', dead),
    ]) {
      await settings.addHost(HostEntry(name: name, hostAddress: address));
    }
    await settings.setActiveIndex(0);
    authStatusProbe = () async => switch (settings.activeHost) {
      claimed => const AuthStatus(setupComplete: true),
      dead => throw TimeoutException('no answer'),
      _ => const AuthStatus(setupComplete: false),
    };
  });

  tearDown(() async {
    authStatusProbe = AuthService.checkStatus;
    authHttpClientFactory = () => sharedHttpClient;
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  Future<void> pumpSetup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: AppRoutes.setup,
      routes: [
        GoRoute(
          path: AppRoutes.setup,
          builder: (_, _) => SetupPage(onSetupComplete: () {}),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('an unclaimed Quark shows the switcher above the form', (
    tester,
  ) async {
    await pumpSetup(tester);

    expect(find.byType(HostSwitcher), findsOneWidget);
    expect(find.text('Fresh'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.byType(QuarkDisconnectedBanner), findsNothing);
  });

  testWidgets('switching to a claimed Quark goes to login', (tester) async {
    await pumpSetup(tester);

    await settings.setActiveIndex(1);
    await tester.pumpAndSettle();

    expect(find.text('login'), findsOneWidget);
    expect(find.byType(SetupPage), findsNothing);
  });

  testWidgets('switching to an unreachable Quark shows the banner', (
    tester,
  ) async {
    await pumpSetup(tester);

    await settings.setActiveIndex(2);
    await tester.pumpAndSettle();

    expect(find.byType(QuarkDisconnectedBanner), findsOneWidget);
    expect(find.byType(SetupPage), findsOneWidget);

    // And switching back to a healthy one clears it.
    await settings.setActiveIndex(0);
    await tester.pumpAndSettle();

    expect(find.byType(QuarkDisconnectedBanner), findsNothing);
  });

  testWidgets('landing on a claimed Quark goes to login', (tester) async {
    await settings.setActiveIndex(1);
    await pumpSetup(tester);

    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('the switcher sits under the heading and above the fields', (
    tester,
  ) async {
    await pumpSetup(tester);

    final heading = tester.getTopLeft(find.text('Set up your quark')).dy;
    final switcher = tester.getTopLeft(find.byType(HostSwitcher)).dy;
    final username = tester
        .getTopLeft(find.widgetWithText(TextFormField, 'Username'))
        .dy;
    expect(heading, lessThan(switcher));
    expect(switcher, lessThan(username));
  });

  testWidgets('retry after an unreachable probe asks again', (tester) async {
    await settings.setActiveIndex(2);
    var probes = 0;
    final unreachable = authStatusProbe;
    authStatusProbe = () {
      probes++;
      return unreachable();
    };
    await pumpSetup(tester);
    expect(probes, 1);

    await tester.tap(find.byKey(const ValueKey('disconnected_banner_retry')));
    await tester.pumpAndSettle();

    expect(probes, 2);
  });

  testWidgets('retry after an unreachable submit submits again', (
    tester,
  ) async {
    final client = _SilentClient();
    authHttpClientFactory = () => client;
    await pumpSetup(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'owner');
    await tester.enterText(fields.at(1), 'correct-horse-battery');
    await tester.enterText(fields.at(2), 'correct-horse-battery');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(QuarkDisconnectedBanner), findsOneWidget);
    expect(client.requests, 1);

    await tester.tap(find.byKey(const ValueKey('disconnected_banner_retry')));
    await tester.pumpAndSettle();

    expect(client.requests, 2);
  });
}

/// A Quark that never answers, counting the requests it swallows.
class _SilentClient extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return Future<http.StreamedResponse>.error(TimeoutException('no answer'));
  }
}
