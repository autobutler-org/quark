import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/snapshot_backup_dialog.dart';
import 'package:quark/widgets/storage_devices/role_dialog.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

/// The Storage tab shows the protection status the Quark reported and follows
/// its next step into the existing drive dialogs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const devices = {
    'devices': [
      {
        'name': 'Stick',
        'devicePath': '/dev/sdb1',
        'mountPoint': '/mnt/stick',
        'fileSystem': 'exfat',
        'isInternal': false,
        'isEnabled': true,
        'role': 'unassigned',
        'usbInfo': {'serial': 'USB1'},
      },
      {
        'name': 'Backups',
        'devicePath': '/dev/sdc1',
        'mountPoint': '/mnt/backups',
        'fileSystem': 'ext4',
        'isInternal': false,
        'isEnabled': true,
        'role': 'snapshot-backup',
        'usbInfo': {'serial': 'USB2'},
      },
    ],
  };

  setUpAll(mockSecureStorage);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': 'http://quark.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
  });

  tearDown(() {
    AppSettings.instance.isAdmin.value = false;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  void serve(Map<String, Object?> protection) {
    sharedHttpClientFactory = () => MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v0/storage/devices/status') {
        return http.Response(jsonEncode(devices), 200);
      }
      if (path == '/api/v0/storage/protection') {
        return http.Response(jsonEncode(protection), 200);
      }
      return http.Response(jsonEncode({'error': ''}), 404);
    });
  }

  Future<void> pumpTab(WidgetTester tester) async {
    setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StorageTab())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an admin follows assign-backup-role into Set Role', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    serve({
      'level': 'unprotected',
      'sentence': 'Your files are only on this Quark.',
      'nextStep': 'assign-backup-role',
      'drives': [
        {
          'serial': 'USB2',
          'name': 'Vault disk',
          'counts': false,
          'reason': 'No completed backup yet.',
          'lastBackedUp': null,
        },
      ],
    });

    await pumpTab(tester);

    expect(find.text('Your files are only on this Quark.'), findsOneWidget);
    expect(find.text('Vault disk'), findsOneWidget);
    expect(find.text('No completed backup yet.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('data_protection_badge')),
        matching: find.text('Unprotected'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Assign the backup role'));
    await tester.pumpAndSettle();

    expect(find.byType(RoleDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an admin follows start-backup into the backup dialog', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    serve({
      'level': 'basic',
      'sentence': 'Start a backup on your other backup drive.',
      'nextStep': 'start-backup',
      'drives': [
        {
          'serial': 'USB2',
          'name': 'Vault disk',
          'counts': false,
          'reason': 'No completed backup yet.',
          'lastBackedUp': null,
        },
      ],
    });

    await pumpTab(tester);

    expect(
      find.text('Start a backup on your other backup drive.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Start a backup'));
    await tester.pumpAndSettle();

    expect(find.byType(SnapshotBackupDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-admin reads the card and the explainer', (tester) async {
    AppSettings.instance.isAdmin.value = false;
    serve({
      'level': 'protected',
      'sentence':
          'Your files are on 3 drives. Keep one backup drive somewhere else.',
      'nextStep': 'keep-one-elsewhere',
      'drives': [
        {
          'serial': 'USB2',
          'name': 'Vault disk',
          'counts': true,
          'reason': '',
          'lastBackedUp': '2026-10-01T12:00:00Z',
        },
      ],
    });

    await pumpTab(tester);

    expect(
      find.text(
        'Your files are on 3 drives. Keep one backup drive somewhere else.',
      ),
      findsWidgets,
    );
    expect(find.text('Assign the backup role'), findsNothing);
    expect(find.text('Start a backup'), findsNothing);
    expect(find.text('Back Up'), findsNothing);
    expect(find.byKey(const ValueKey('data_protection_badge')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('data_protection_next_step')));
    await tester.pumpAndSettle();

    expect(find.text('Why two backup drives?'), findsWidgets);
    expect(find.text('One copy'), findsOneWidget);
    expect(
      find.text('A fire, a theft, or a failed drive takes everything.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('quark_sheet_close')));
    await tester.pumpAndSettle();
    expect(find.text('One copy'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('data_protection_explain')));
    await tester.pumpAndSettle();
    expect(find.text('One copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
