import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

/// #3084: the Storage tab polls a snapshot backup's status every two seconds.
/// A 404 means the job is gone for good, so the poll stops and the tab drops
/// the job; any other error is one bad moment, so the poll keeps going.
///
/// #4037: a backup the device list reports is followed too, wherever it was
/// started. Its progress is on the receiving drive's card, the drive's
/// actions wait for it, and the progress goes once it finishes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const statusPath = '/api/v0/storage/devices/snapshot-backup/status/job-1';
  const pollEvery = Duration(seconds: 2);

  late int statusCalls;
  late int statusCode;

  /// The job id the device list reports for the backup drive, if any.
  late String? activeJobId;

  /// The status the job reports.
  late String jobStatus;

  setUpAll(mockSecureStorage);

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
    statusCode = 200;
    activeJobId = null;
    jobStatus = 'COPYING';
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
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
                  'activeBackupJobId': ?activeJobId,
                },
                // A data drive to copy: with none, Start Backup is off.
                {
                  'name': 'Built-in storage',
                  'isInternal': true,
                  'mountPoint': '/',
                  'role': 'unassigned',
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
            jsonEncode({
              'id': 'job-1',
              'status': jobStatus,
              'progress': 0.42,
              'targetName': 'Backup A',
              'sourceNames': ['Built-in storage', 'Photos'],
              'currentSource': 'Built-in storage',
            }),
            statusCode,
          );
      }
      return http.Response(jsonEncode({'error': ''}), 404);
    });
  });

  tearDown(() {
    AppSettings.instance.isAdmin.value = false;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Starts a backup from the tab and confirms it, leaving the job polling.
  Future<void> startBackup(WidgetTester tester) async {
    setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StorageTab())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back up onto this drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Backup'));
    await tester.pump();
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

  testWidgets(
    'a backup started elsewhere shows, holds the actions, and clears',
    (tester) async {
      activeJobId = 'job-1';
      setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StorageTab())),
      );
      await tester.pumpAndSettle();
      await poll(tester, 1);

      expect(
        find.text('Copying Built-in storage onto Backup A · 42%'),
        findsOneWidget,
      );
      final backUp = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Back up onto this drive'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(backUp.onPressed, isNull);

      activeJobId = null;
      jobStatus = 'COMPLETED';
      await poll(tester, 1);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('backup_progress_text')), findsNothing);
      expect(find.text('Backup completed successfully'), findsOneWidget);
      final after = statusCalls;
      await poll(tester, 3);
      expect(statusCalls, after, reason: 'polled a finished backup');
      expect(tester.takeException(), isNull);
    },
  );
}
