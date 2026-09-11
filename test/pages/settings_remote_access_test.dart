import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/unreachable_quark.dart';

/// #1815: remote access being switched on and the node being on the tailnet
/// are separate facts, and the section shows which one the Quark is in.
void main() {
  final settings = AppSettings.instance;

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  late HttpOverrides? priorOverrides;

  Future<void> reset() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.setSessionToken(null);
  }

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await reset();
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    await reset();
  });

  /// Answers the remote-access status with [status]; every other section's
  /// request gets a 404 it can fail on.
  Future<void> pumpWithStatus(
    WidgetTester tester,
    Map<String, dynamic> status,
  ) async {
    sharedHttpClientFactory = () => MockClient(
      (request) async => request.url.path == '/api/v0/settings/remote-access'
          ? http.Response(jsonEncode(status), 200)
          : http.Response('', 404),
    );
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-session');

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Settings overflows its own app bar at any viewport; ignore only that.
    final priorOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = priorOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      priorOnError?.call(details);
    };

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('marks the section experimental', (tester) async {
    await pumpWithStatus(tester, {'enabled': false, 'connected': false});

    expect(
      find.byKey(const ValueKey('settings_remote_access_experimental')),
      findsOneWidget,
    );
    expect(find.text('Enable remote access'), findsOneWidget);
  });

  testWidgets('shows connecting while on but not on the tailnet', (
    tester,
  ) async {
    await pumpWithStatus(tester, {'enabled': true, 'connected': false});

    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.text('Connected via Tailscale'), findsNothing);
    expect(find.text('Disable'), findsOneWidget);
  });

  testWidgets('shows a failed start without its diagnostic', (tester) async {
    await pumpWithStatus(tester, {
      'enabled': true,
      'connected': false,
      'error': 'failed to start tsnet: listen tcp: address in use',
    });

    expect(find.text(Errors.remoteAccessFailing), findsOneWidget);
    expect(find.textContaining('tsnet'), findsNothing);
    expect(find.text('Connecting…'), findsNothing);
  });

  testWidgets('shows the URL once connected', (tester) async {
    await pumpWithStatus(tester, {
      'enabled': true,
      'connected': true,
      'remoteUrl': 'http://100.64.0.7:80',
    });

    expect(find.text('Connected via Tailscale'), findsOneWidget);
    expect(find.text('http://100.64.0.7:80'), findsOneWidget);
  });
}
