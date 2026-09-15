import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/storage_devices_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1928: every drive action on the Devices page is admin-only on the Quark,
/// so a non-admin was offered buttons that could only answer with a refusal.
/// The page leaves the action callbacks unset for them, and the body draws no
/// button for an unset callback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': 'http://quark.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
  });

  const unmounted = StorageDevice(
    name: 'Stick',
    devicePath: '/dev/sdb1',
    mountPoint: '/mnt/stick',
    fileSystem: 'exfat',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: false,
    isEnabled: false,
    serial: 'USB1',
  );
  const backupDrive = StorageDevice(
    name: 'Backups',
    devicePath: '/dev/sdc1',
    mountPoint: '/mnt/backups',
    fileSystem: 'ext4',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: false,
    isEnabled: true,
    serial: 'USB2',
    role: 'snapshot-backup',
  );

  Future<void> pumpBody(
    WidgetTester tester, {
    ValueChanged<StorageDevice>? onMount,
    ValueChanged<StorageDevice>? onSetRole,
    ValueChanged<StorageDevice>? onBackup,
    ValueChanged<StorageDevice>? onVerify,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageDevicesBody(
            devices: const [unmounted, backupDrive],
            error: null,
            mounting: const {},
            vaultDeviceSerial: '',
            backupStatus: null,
            activeBackupJobId: null,
            onRefresh: () async {},
            onRetry: () {},
            onManageHosts: () {},
            onMount: onMount,
            onSetRole: onSetRole,
            onBackup: onBackup,
            onVerify: onVerify,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an admin gets every drive action', (tester) async {
    final actions = <String>[];
    await pumpBody(
      tester,
      onMount: (d) => actions.add('mount ${d.serial}'),
      onSetRole: (d) => actions.add('role ${d.serial}'),
      onBackup: (d) => actions.add('backup ${d.serial}'),
      onVerify: (d) => actions.add('verify ${d.serial}'),
    );

    for (final label in ['Mount', 'Set Role', 'Back Up', 'Verify']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }

    expect(actions, ['mount USB1', 'role USB2', 'backup USB2', 'verify USB2']);
  });

  testWidgets('a non-admin sees the drives and no actions', (tester) async {
    await pumpBody(tester);

    expect(find.text('Stick'), findsOneWidget);
    expect(find.text('Backups'), findsOneWidget);
    for (final label in ['Mount', 'Set Role', 'Back Up', 'Verify']) {
      expect(find.text(label), findsNothing, reason: '$label is offered');
    }
    expect(tester.takeException(), isNull);
  });
}
