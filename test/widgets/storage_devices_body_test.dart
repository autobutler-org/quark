import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/data_protection_service.dart';
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
    ValueChanged<StorageDevice>? onRestore,
    DataProtectionStatus? protection,
    Map<String, BackupJobStatus> backupStatuses = const {},
  }) async {
    setViewport(tester, const Size(1280, 800));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageDevicesBody(
            devices: devices,
            error: null,
            mounting: const {},
            onRefresh: () async {},
            onRetry: () {},
            onManageHosts: () {},
            onMount: onMount,
            onSetRole: onSetRole,
            onBackup: onBackup,
            onVerify: onVerify,
            onRestore: onRestore,
            protection: protection,
            backupStatuses: backupStatuses,
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

    for (final label in [
      'Mount',
      'Set Role',
      'Back up onto this drive',
      'Verify',
    ]) {
      await tester.tap(find.text(label));
      await tester.pump();
    }

    expect(actions, ['mount USB1', 'role USB2', 'backup USB2', 'verify USB2']);
  });

  testWidgets('a non-admin sees the drives and no actions', (tester) async {
    await pumpBody(tester);

    expect(find.text('Stick'), findsOneWidget);
    expect(find.text('Backups'), findsOneWidget);
    for (final label in [
      'Mount',
      'Set Role',
      'Back up onto this drive',
      'Verify',
      'Restore vaults',
    ]) {
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

  testWidgets('restore vaults is only on the snapshot-backup drive', (
    tester,
  ) async {
    await pumpBody(
      tester,
      devices: const [builtIn, backupDrive],
      onRestore: (_) {},
    );

    expect(find.text('Restore vaults'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('device_card_restore_USB2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('device_card_restore_')), findsNothing);
  });

  // #4037: a data drive shows its own copies, a backup drive what it holds,
  // and neither carries the whole Quark's level.
  testWidgets('each drive shows its own backup state and no level badge', (
    tester,
  ) async {
    final copiedAt = DateTime(2026, 11, 2, 12);
    await pumpBody(
      tester,
      devices: const [builtIn, backupDrive],
      onBackup: (_) {},
      protection: DataProtectionStatus(
        level: 'basic',
        sentence: 'Every drive has a copy on one backup drive.',
        action: DataProtectionAction.startBackup,
        dataDrives: [
          DataProtectionDataDrive(
            serial: '',
            name: 'Built-in storage',
            level: 'basic',
            copies: [
              DataProtectionCopy(
                backupSerial: 'USB2',
                backupName: 'Backups',
                copiedAt: copiedAt,
                counts: true,
              ),
            ],
          ),
        ],
        backupDrives: [
          DataProtectionBackupDrive(
            serial: 'USB2',
            name: 'Backups',
            state: DataProtectionBackupState.behind,
            holds: [
              DataProtectionHeldCopy(
                serial: '',
                name: 'Built-in storage',
                copiedAt: copiedAt,
              ),
            ],
            newestCopy: copiedAt,
          ),
        ],
      ),
    );

    expect(find.text('Backed up Nov 2 · Backups'), findsOneWidget);
    expect(
      find.text(
        'Holds copies of Built-in storage. Newest Nov 2. '
        'Back up onto this drive to bring it up to date.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back up onto this drive'), findsOneWidget);
    for (final level in ['Unprotected', 'Basic', 'Protected']) {
      expect(find.text(level), findsNothing, reason: '$level badge drawn');
    }

    await tester.tap(find.text('Backed up Nov 2 · Backups'));
    await tester.pump();
    expect(find.text('Backups · Nov 2'), findsOneWidget);
  });

  testWidgets('a drive with no copies reads as not backed up', (tester) async {
    await pumpBody(
      tester,
      devices: const [builtIn, backupDrive],
      protection: const DataProtectionStatus(
        level: 'unprotected',
        sentence: 'Built-in storage is only on this Quark.',
        action: DataProtectionAction.startBackup,
        dataDrives: [
          DataProtectionDataDrive(
            serial: '',
            name: 'Built-in storage',
            level: 'unprotected',
          ),
        ],
        backupDrives: [
          DataProtectionBackupDrive(
            serial: 'USB2',
            name: 'Backups',
            state: DataProtectionBackupState.noCopies,
          ),
        ],
      ),
    );

    expect(find.text('Not backed up'), findsOneWidget);
    expect(find.text('No copies yet.'), findsOneWidget);
  });

  testWidgets('progress names the drives on the receiving card', (
    tester,
  ) async {
    await pumpBody(
      tester,
      devices: const [builtIn, backupDrive],
      backupStatuses: const {
        'USB2': BackupJobStatus(
          id: '7',
          status: 'COPYING',
          progress: 0.42,
          totalFiles: 10,
          filesCopied: 4,
          filesSkipped: 0,
          totalBytes: 100,
          bytesCopied: 42,
          targetName: 'Backup A',
          sourceNames: ['Built-in storage', 'Photos'],
          currentSource: 'Built-in storage',
        ),
      },
    );

    expect(
      find.text('Copying Built-in storage onto Backup A · 42%'),
      findsOneWidget,
    );
  });
}
