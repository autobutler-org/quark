import 'dart:convert';

import 'package:material_ui/material_ui.dart';
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
/// its next step into the existing drive dialogs. Back up now starts onto
/// each connected backup drive, and no drive card carries the level (#4037).
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

  /// The target of every backup the tab started.
  final started = <String>[];

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
    started.clear();
  });

  tearDown(() {
    AppSettings.instance.isAdmin.value = false;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  void serve(
    Map<String, Object?> protection, {
    Map<String, Object?>? devicesBody,
  }) {
    sharedHttpClientFactory = () => MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v0/storage/devices/status') {
        return http.Response(jsonEncode(devicesBody ?? devices), 200);
      }
      if (path == '/api/v0/storage/protection') {
        return http.Response(jsonEncode(protection), 200);
      }
      if (path == '/api/v0/storage/devices/snapshot-backup') {
        started.add(jsonDecode(request.body)['targetDeviceSerial'] as String);
        return http.Response(jsonEncode({'jobId': '${started.length}'}), 202);
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
      'dataDrives': [
        {'serial': 'USB1', 'name': 'Stick', 'level': 'unprotected'},
      ],
      'backupDrives': [
        {
          'serial': 'USB2',
          'name': 'Backups',
          'state': 'no-copies',
          'holds': <Object?>[],
          'newestCopy': null,
        },
      ],
    });

    await pumpTab(tester);

    expect(find.text('Your files are only on this Quark.'), findsOneWidget);
    expect(find.text('Not backed up'), findsOneWidget);
    expect(find.text('No copies yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('data_protection_badge')), findsNothing);

    await tester.tap(find.text('Assign the backup role'));
    await tester.pumpAndSettle();

    expect(find.byType(RoleDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back up now starts onto each connected backup drive', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    Map<String, Object?> backup(String serial, String state) => {
      'serial': serial,
      'name': serial,
      'state': state,
      'holds': <Object?>[],
      'newestCopy': null,
    };
    serve({
      'level': 'basic',
      'sentence':
          'Every drive has a copy on one backup drive. Back up onto your other backup drive.',
      'nextStep': 'start-backup',
      'dataDrives': <Object?>[],
      'backupDrives': [
        backup('USB2', 'behind'),
        backup('AWAY', 'away'),
        backup('BUSY', 'receiving'),
      ],
    });

    await pumpTab(tester);

    expect(find.text('Start a backup'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('data_protection_back_up_now')));
    await tester.pumpAndSettle();

    expect(find.byType(SnapshotBackupDialog), findsNothing);
    expect(started, ['USB2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-admin reads the card and the explainer', (tester) async {
    AppSettings.instance.isAdmin.value = false;
    serve({
      'level': 'protected',
      'sentence':
          'Your files are on 3 drives. Keep one backup drive somewhere else.',
      'nextStep': 'keep-one-elsewhere',
      'dataDrives': <Object?>[],
      'backupDrives': [
        {
          'serial': 'USB2',
          'name': 'Backups',
          'state': 'current',
          'holds': <Object?>[],
          'newestCopy': null,
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
    expect(find.text('Back up onto this drive'), findsNothing);
    expect(find.text('Back up now'), findsNothing);
    expect(find.byKey(const ValueKey('data_protection_badge')), findsNothing);

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

  const builtIn = {
    'name': 'Quark',
    'devicePath': '/dev/mmcblk0p2',
    'mountPoint': '/',
    'fileSystem': 'ext4',
    'isInternal': true,
    'isEnabled': true,
    'role': 'unassigned',
  };
  Map<String, Object?> stick(String role) => {
    'name': 'Stick',
    'devicePath': '/dev/sdb1',
    'mountPoint': '/mnt/stick',
    'fileSystem': 'exfat',
    'isInternal': false,
    'isEnabled': true,
    'role': role,
    'usbInfo': {'serial': 'USB1'},
  };
  const assignRole = {
    'level': 'unprotected',
    'sentence': 'Your files are only on this Quark.',
    'nextStep': 'assign-backup-role',
  };

  testWidgets('assign-backup-role skips built-in storage while it is main', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    serve(
      assignRole,
      devicesBody: {
        'devices': [builtIn, stick('unassigned')],
      },
    );

    await pumpTab(tester);
    await tester.tap(find.text('Assign the backup role'));
    await tester.pumpAndSettle();

    expect(find.byType(RoleDialog), findsOneWidget);
    expect(
      tester.widget<RoleDialog>(find.byType(RoleDialog)).isInternal,
      false,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('assign-backup-role offers built-in once a USB drive is main', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    serve(
      assignRole,
      devicesBody: {
        'devices': [builtIn, stick('default-storage')],
      },
    );

    await pumpTab(tester);
    await tester.tap(find.text('Assign the backup role'));
    await tester.pumpAndSettle();

    expect(tester.widget<RoleDialog>(find.byType(RoleDialog)).isInternal, true);
    expect(find.text('Other drives are backed up onto it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assign-backup-role is not offered on the main drive alone', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    serve(
      assignRole,
      devicesBody: {
        'devices': [builtIn],
      },
    );

    await pumpTab(tester);

    expect(find.text('Assign the backup role'), findsNothing);
  });
}
