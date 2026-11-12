import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/restore_vault_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

const _runsPath = '/api/v0/storage/devices/snapshot-backup/runs';

/// #4044: an admin sees each backup drive's backups on its card, collapsed
/// at first, and deletes one after a confirm; a deletion anywhere reloads
/// the backups and the protection status. #4032: Restore vaults names the
/// backup it reads and can read another.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, Object?>> runs;
  late int deleteStatus;
  late List<Object?> deletes;
  late int runsCalls;
  late int protectionCalls;
  late StreamController<FileEvent> events;

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
    runs = [
      {
        'folder': '2026-11-02 09.00',
        'completedAt': '2026-11-02T12:00:00Z',
        'sizeBytes': 2048,
        'drives': [
          {'folder': 'Built-in storage', 'serial': '', 'name': ''},
        ],
      },
      {
        'folder': '2026-10-26 09.00',
        'completedAt': '2026-10-26T12:00:00Z',
        'sizeBytes': 1024,
        'drives': [
          {'folder': 'Built-in storage', 'serial': '', 'name': ''},
        ],
      },
    ];
    deleteStatus = 200;
    deletes = [];
    runsCalls = 0;
    protectionCalls = 0;
    events = StreamController<FileEvent>.broadcast(sync: true);
    addTearDown(events.close);
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      switch ((request.method, request.url.path)) {
        case (_, '/api/v0/storage/devices/status'):
          return http.Response(
            jsonEncode({
              'devices': [
                {
                  'name': 'Backups',
                  'usbInfo': {'serial': 'USB2'},
                  'mountPoint': '/mnt/backups',
                  'role': 'snapshot-backup',
                  'isEnabled': true,
                },
              ],
            }),
            200,
          );
        case (_, '/api/v0/storage/protection'):
          protectionCalls++;
          return http.Response(
            jsonEncode({'level': 'basic', 'sentence': 'One copy.'}),
            200,
          );
        case ('GET', _runsPath):
          runsCalls++;
          return http.Response(jsonEncode({'runs': runs}), 200);
        case ('DELETE', _runsPath):
          final body = jsonDecode(request.body) as Map<String, Object?>;
          deletes.add(body);
          if (deleteStatus != 200) {
            return http.Response(
              jsonEncode({'error': 'the drive is busy'}),
              deleteStatus,
            );
          }
          runs.removeWhere((r) => r['folder'] == body['run']);
          return http.Response(jsonEncode({'run': body}), 200);
      }
      return http.Response(jsonEncode({'error': ''}), 404);
    });
  });

  tearDown(() {
    AppSettings.instance.isAdmin.value = false;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    RestoreVaultController? restoreVault,
  }) async {
    setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageTab(events: events.stream, restoreVault: restoreVault),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const summary = ValueKey('backup_runs_USB2');
  const deleteOlder = ValueKey('backup_run_delete_USB2_1');

  testWidgets('the backups are collapsed, then each run shows', (tester) async {
    await pumpTab(tester);

    expect(find.text('2 backups · newest Nov 2'), findsOneWidget);
    expect(find.text('Oct 26, 09.00'), findsNothing);

    await tester.tap(find.byKey(summary));
    await tester.pumpAndSettle();

    expect(find.text('Nov 2, 09.00'), findsOneWidget);
    expect(find.text('Oct 26, 09.00'), findsOneWidget);
    expect(find.text('1.0 KB · Built-in storage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete asks first, then reloads the backups and protection', (
    tester,
  ) async {
    await pumpTab(tester);
    await tester.tap(find.byKey(summary));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(deleteOlder));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be undone"), findsOneWidget);
    expect(find.textContaining('free less space'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete_backup_run_cancel')));
    await tester.pumpAndSettle();
    expect(deletes, isEmpty);

    final protectionBefore = protectionCalls;
    await tester.tap(find.byKey(deleteOlder));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete_backup_run_confirm')));
    await tester.pumpAndSettle();

    expect(deletes, [
      {'deviceSerial': 'USB2', 'run': '2026-10-26 09.00'},
    ]);
    expect(find.text('Deleted the backup of Oct 26, 09.00.'), findsOneWidget);
    expect(find.text('1 backup · newest Nov 2'), findsOneWidget);
    expect(find.text('Oct 26, 09.00'), findsNothing);
    expect(protectionCalls, greaterThan(protectionBefore));
  });

  testWidgets('a busy drive says so and keeps the backup', (tester) async {
    deleteStatus = 409;
    await pumpTab(tester);
    await tester.tap(find.byKey(summary));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(deleteOlder));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete_backup_run_confirm')));
    await tester.pumpAndSettle();

    expect(find.text(Errors.backupDriveBusy), findsOneWidget);
    expect(find.text('Oct 26, 09.00'), findsOneWidget);
  });

  testWidgets('backup_deleted reloads the backups and protection', (
    tester,
  ) async {
    await pumpTab(tester);
    final runsBefore = runsCalls;
    final protectionBefore = protectionCalls;

    runs.removeLast();
    events.add(
      const FileEvent(
        kind: 'backup_deleted',
        path: '',
        data: {'deviceSerial': 'USB2', 'run': '2026-10-26 09.00'},
      ),
    );
    await tester.pumpAndSettle();

    expect(runsCalls, greaterThan(runsBefore));
    expect(protectionCalls, greaterThan(protectionBefore));
    expect(find.text('1 backup · newest Nov 2'), findsOneWidget);
  });

  testWidgets('a non-admin sees no backups and lists none', (tester) async {
    AppSettings.instance.isAdmin.value = false;
    await pumpTab(tester);

    expect(find.byKey(summary), findsNothing);
    expect(runsCalls, 0);
  });

  testWidgets('Restore vaults names the newest backup and sends the picked', (
    tester,
  ) async {
    final calls = <String?>[];
    final restore = RestoreVaultController(
      restoreVault:
          ({
            required String deviceSerial,
            required String password,
            String? run,
          }) async {
            calls.add(run);
            return VaultRestoreResult(accounts: 1, items: 2, run: run);
          },
    );
    addTearDown(restore.dispose);
    await pumpTab(tester, restoreVault: restore);

    await tester.tap(find.byKey(const ValueKey('device_card_restore_USB2')));
    await tester.pumpAndSettle();
    expect(find.text('From the backup of Nov 2, 09.00.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('backup_run_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oct 26, 09.00 · 1.0 KB').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('restore_vault_password')),
      'secret',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore_vault_confirm')));
    await tester.pumpAndSettle();

    expect(calls, ['2026-10-26 09.00']);
    expect(
      find.text('Restored 1 vault and 2 entries, backed up Oct 26, 09.00.'),
      findsOneWidget,
    );
  });
}
