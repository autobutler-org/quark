import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/auth_salt.dart';

/// #3084: the Storage tab polls a snapshot backup's status every two seconds.
/// A 404 means the job is gone for good, so the poll stops and the tab drops
/// the job; any other error is one bad moment, so the poll keeps going.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const statusPath = '/api/v0/storage/devices/snapshot-backup/status/job-1';
  const pollEvery = Duration(seconds: 2);

  late int statusCalls;
  late int statusCode;

  setUpAll(() async {
    await ChatCrypto.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': 'http://quark.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    AppSettings.instance.isAdmin.value = true;
    StorageService.invalidateDeviceCache();
    statusCalls = 0;
    resetSharedHttpClient();
    sharedHttpClientFactory = () => AuthSaltClient(
      MockClient((request) async {
        switch (request.url.path) {
          case '/api/v0/storage/devices/status':
            return http.Response(
              jsonEncode({
                'devices': [
                  {
                    'name': 'Backups',
                    'serial': 'USB2',
                    'mountPoint': '/mnt/backups',
                    'role': 'snapshot-backup',
                    'isEnabled': true,
                  },
                ],
              }),
              200,
            );
          case '/api/v0/storage/devices/snapshot-backup':
            return http.Response(jsonEncode({'jobId': 'job-1'}), 200);
          case statusPath:
            statusCalls++;
            return http.Response(
              jsonEncode({'id': 'job-1', 'status': 'COPYING'}),
              statusCode,
            );
        }
        return http.Response(jsonEncode({'error': ''}), 404);
      }),
    );
  });

  tearDown(() {
    AppSettings.instance.isAdmin.value = false;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    authHttpClientFactory = () => sharedHttpClient;
  });

  /// Starts a backup from the tab and answers the two dialogs, leaving the
  /// job polling.
  Future<void> startBackup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StorageTab())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back Up'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'grace');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Backup'));
    // Deriving the auth key needs the real event loop as well as the fake one.
    await pumpWhileDeriving(tester);
  }

  /// Lets [ticks] poll intervals go by.
  Future<void> poll(WidgetTester tester, int ticks) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(pollEvery);
    }
  }

  testWidgets('a 404 stops the poll and drops the job', (tester) async {
    statusCode = 404;
    await startBackup(tester);
    await poll(tester, 1);
    final callsAt404 = statusCalls;
    expect(callsAt404, greaterThan(0), reason: 'the poll never started');

    await poll(tester, 5);

    expect(statusCalls, callsAt404, reason: 'polled again after a 404');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 500 keeps the poll going', (tester) async {
    statusCode = 500;
    await startBackup(tester);
    await poll(tester, 1);
    final callsAt500 = statusCalls;
    expect(callsAt500, greaterThan(0), reason: 'the poll never started');

    await poll(tester, 4);

    expect(statusCalls, callsAt500 + 4, reason: 'the poll stopped on a 500');
    expect(tester.takeException(), isNull);
  });
}
