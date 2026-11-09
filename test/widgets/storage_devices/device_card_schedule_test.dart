import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/device_card.dart';

/// #3984: a backup drive's card says how often it backs up, and that a due
/// backup waits for the drive, and offers Schedule when it is given one.
void main() {
  const drive = StorageDevice(
    name: 'Backups',
    devicePath: '/dev/sdb1',
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

  Future<void> pumpCard(
    WidgetTester tester, {
    BackupSchedule? schedule,
    VoidCallback? onSchedule,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DeviceCard(
          device: drive,
          isMounting: false,
          schedule: schedule,
          onSchedule: onSchedule,
        ),
      ),
    ),
  );

  const text = ValueKey('device_card_schedule_text_USB2');

  testWidgets('says how often the drive backs up', (tester) async {
    await pumpCard(
      tester,
      schedule: const BackupSchedule(cadence: BackupCadence.weekly),
    );

    expect(tester.widget<Text>(find.byKey(text)).data, 'Backs up weekly.');
  });

  testWidgets('says a due backup waits for the drive', (tester) async {
    await pumpCard(
      tester,
      schedule: const BackupSchedule(
        cadence: BackupCadence.daily,
        waitingForDrive: true,
      ),
    );

    expect(
      tester.widget<Text>(find.byKey(text)).data,
      'Backs up daily. Due, will run when plugged in.',
    );
  });

  testWidgets('says nothing with the schedule off', (tester) async {
    await pumpCard(tester, schedule: const BackupSchedule());

    expect(find.byKey(text), findsNothing);
  });

  testWidgets('Schedule shows only with a callback, and calls it', (
    tester,
  ) async {
    const button = ValueKey('device_card_schedule_USB2');
    await pumpCard(tester);
    expect(find.byKey(button), findsNothing);

    var opened = 0;
    await pumpCard(tester, onSchedule: () => opened++);
    await tester.tap(find.byKey(button));

    expect(opened, 1);
  });
}
