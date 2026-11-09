import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/restore_files_controller.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/device_card.dart';
import 'package:quark/widgets/storage_devices/restore_files_flow.dart';

/// #4009: a snapshot-backup drive's card offers Restore files, which asks
/// first and then says where the files are going.
void main() {
  const backup = StorageDevice(
    name: 'Backup',
    devicePath: '/dev/sdb1',
    mountPoint: '/mnt/backup',
    fileSystem: 'ext4',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: false,
    isEnabled: true,
    serial: 'BACKUP1',
  );
  const buttonKey = ValueKey('device_card_restore_files_BACKUP1');

  testWidgets('restores after the confirm and shows the summary', (
    tester,
  ) async {
    final calls = <(String, bool)>[];
    final controller = RestoreFilesController(
      restoreFiles:
          ({
            required String deviceSerial,
            required bool missingToBuiltIn,
            String? run,
          }) async {
            calls.add((deviceSerial, missingToBuiltIn));
            return const FilesRestoreResult(
              jobId: '1',
              folders: [(folder: 'internal', toBuiltIn: false)],
            );
          },
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => DeviceCard(
              device: backup,
              isMounting: false,
              onRestoreFiles: () =>
                  restoreFilesFrom(context, backup, controller: controller),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore_files_cancel')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore_files_confirm')));
    await tester.pumpAndSettle();
    expect(calls, [('BACKUP1', false)]);
    expect(find.text('Restoring files from 1 drive.'), findsOneWidget);
  });

  testWidgets('a running backup disables it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceCard(
            device: backup,
            isMounting: false,
            isBackupRunning: true,
            onRestoreFiles: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<ButtonStyleButton>(find.byKey(buttonKey)).onPressed,
      isNull,
    );
  });
}
