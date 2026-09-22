import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The login page says a Quark is unreachable as soon as its status check
/// fails, not only after a sign-in attempt, and its retry repeats that check —
/// the same as the setup page.
void main() {
  final settings = AppSettings.instance;
  var reachable = false;
  var probes = 0;

  setUp(() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://localhost:8094'),
    );
    reachable = false;
    probes = 0;
    authStatusProbe = () async {
      probes++;
      if (!reachable) throw TimeoutException('no answer');
      return const AuthStatus(setupComplete: true);
    };
  });

  tearDown(() async {
    authStatusProbe = AuthService.checkStatus;
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  testWidgets('an unreachable Quark shows the banner and retry re-probes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          onLoginSuccess: () {},
          checkStatus: () async => const AuthStatus(setupComplete: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuarkDisconnectedBanner), findsOneWidget);
    // The #1827 rule: an unanswered probe keeps the setup link.
    expect(find.byKey(const ValueKey('login_set_up_quark')), findsOneWidget);
    expect(probes, 1);

    reachable = true;
    await tester.tap(find.byKey(const ValueKey('disconnected_banner_retry')));
    await tester.pumpAndSettle();

    expect(probes, 2);
    expect(find.byType(QuarkDisconnectedBanner), findsNothing);
    expect(find.byKey(const ValueKey('login_set_up_quark')), findsNothing);
  });
}
