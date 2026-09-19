import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/pages/login_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/router.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A Quark that never answers, which is what an address with nothing behind
/// it looks like to the app.
class _SilentClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future<http.StreamedResponse>.error(TimeoutException('no answer'));
}

/// #2062: signing in against a dead host left "You're not connected" on the
/// page, and switching to a healthy Quark kept showing it until the user
/// pressed Try again — so the new host looked broken too.
void main() {
  final settings = AppSettings.instance;

  setUp(() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.addHost(
      HostEntry(name: 'Broken', hostAddress: 'http://localhost:8099'),
    );
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://localhost:8080'),
    );
    await settings.setActiveIndex(0);
    authHttpClientFactory = _SilentClient.new;
    authStatusProbe = () async => throw TimeoutException('no answer');
  });

  tearDown(() async {
    authHttpClientFactory = () => sharedHttpClient;
    authStatusProbe = AuthService.checkStatus;
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(onLoginSuccess: () {})),
    );
    await tester.pumpAndSettle();
  }

  Future<void> failSignIn(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'ada');
    await tester.enterText(fields.last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('a dead host says so', (tester) async {
    await pumpLogin(tester);
    await failSignIn(tester);

    expect(find.byType(QuarkDisconnectedBanner), findsOneWidget);
  });

  testWidgets('switching to another Quark clears the offline banner', (
    tester,
  ) async {
    await pumpLogin(tester);
    await failSignIn(tester);
    expect(find.byType(QuarkDisconnectedBanner), findsOneWidget);

    await settings.setActiveIndex(1);
    await tester.pumpAndSettle();

    expect(find.byType(QuarkDisconnectedBanner), findsNothing);
  });

  testWidgets('a credential error does not survive the switch either', (
    tester,
  ) async {
    await pumpLogin(tester);
    // A Quark that answers, and refuses.
    authHttpClientFactory = () => _RefusingClient();
    await failSignIn(tester);
    expect(find.text('Invalid username or password.'), findsOneWidget);

    await settings.setActiveIndex(1);
    await tester.pumpAndSettle();

    expect(find.text('Invalid username or password.'), findsNothing);
  });
}

/// A Quark that answers 401, which is a rejected sign-in rather than an
/// unreachable host.
class _RefusingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(const Stream.empty(), 401, request: request);
  }
}
