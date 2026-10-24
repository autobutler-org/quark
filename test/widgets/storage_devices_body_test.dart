import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/storage_devices_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// #1928: every drive action on the Devices page is admin-only on the Quark,
/// so a non-admin was offered buttons that could only answer with a refusal.
/// The page leaves the action callbacks unset for them, and the body draws no
/// button for an unset callback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(mockSecureStorage);

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

  const builtIn = StorageDevice(
    name: 'Built-in',
    devicePath: '/dev/mmcblk0p1',
    mountPoint: '/data',
    fileSystem: 'ext4',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: true,
    isEnabled: true,
  );

  Future<void> pumpBody(
    WidgetTester tester, {
    List<StorageDevice> devices = const [unmounted, backupDrive],
    ValueChanged<StorageDevice>? onMount,
    ValueChanged<StorageDevice>? onSetRole,
    ValueChanged<StorageDevice>? onBackup,
    ValueChanged<StorageDevice>? onVerify,
  }) async {
    setViewport(tester, const Size(1280, 800));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageDevicesBody(
            devices: devices,
            error: null,
            mounting: const {},
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

  // #3194: built-in storage can take the default storage role back, so an
  // admin is offered Set Role on it too.
  testWidgets('an admin can set the role of built-in storage', (tester) async {
    final actions = <String>[];
    await pumpBody(
      tester,
      devices: const [builtIn],
      onSetRole: (d) => actions.add('role "${d.serial}"'),
    );

    await tester.tap(find.text('Set Role'));

    expect(actions, ['role ""']);
  });

  testWidgets('a non-admin gets no Set Role on built-in storage', (
    tester,
  ) async {
    await pumpBody(tester, devices: const [builtIn]);

    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('Set Role'), findsNothing);
  });
}
