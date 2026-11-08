import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/backup_runs_controller.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';

/// #4044: each backup drive's runs, deleting one, and listing again when a
/// backup is deleted anywhere. The Quark is a fake.
void main() {
  late Map<String, List<BackupRun>> onDrive;
  late List<String> listed;
  late List<(String, String)> deleted;
  late Object? deleteError;
  late StreamController<FileEvent> events;

  BackupRunsController build() {
    final controller = BackupRunsController(
      list: (serial) async {
        listed.add(serial);
        final runs = onDrive[serial];
        if (runs == null) throw const ApiException(404);
        return runs;
      },
      delete: ({required String deviceSerial, required String run}) async {
        deleted.add((deviceSerial, run));
        if (deleteError case final error?) throw error;
        onDrive[deviceSerial]!.removeWhere((r) => r.folder == run);
      },
      events: events.stream,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    onDrive = {
      'USB2': [
        const BackupRun(folder: '2026-11-02 09.00'),
        const BackupRun(folder: '2026-10-26 09.00'),
      ],
    };
    listed = [];
    deleted = [];
    deleteError = null;
    events = StreamController<FileEvent>.broadcast(sync: true);
    addTearDown(events.close);
  });

  test('lists each drive and keeps a failure per drive', () async {
    final controller = build();

    await controller.load(['USB2', 'GONE']);

    expect(controller.runsFor('USB2')!.map((r) => r.folder), [
      '2026-11-02 09.00',
      '2026-10-26 09.00',
    ]);
    expect(controller.errorFor('USB2'), isNull);
    expect(controller.runsFor('GONE'), isNull);
    expect(controller.errorFor('GONE'), isA<ApiException>());
  });

  test('a drive no longer loaded is forgotten', () async {
    final controller = build();
    await controller.load(['USB2']);

    await controller.load(const []);

    expect(controller.runsFor('USB2'), isNull);
  });

  test('delete removes the run and lists the drive again', () async {
    final controller = build();
    await controller.load(['USB2']);
    listed.clear();

    final error = await controller.delete('USB2', '2026-10-26 09.00');

    expect(error, isNull);
    expect(deleted, [('USB2', '2026-10-26 09.00')]);
    expect(listed, ['USB2']);
    expect(controller.runsFor('USB2')!.map((r) => r.folder), [
      '2026-11-02 09.00',
    ]);
  });

  test('a busy drive returns the 409 and keeps the runs', () async {
    final controller = build();
    await controller.load(['USB2']);
    deleteError = const ApiException(409);

    final error = await controller.delete('USB2', '2026-10-26 09.00');

    expect(
      Errors.backupRun(error, 'delete the backup'),
      Errors.backupDriveBusy,
    );
    expect(controller.runsFor('USB2'), hasLength(2));
  });

  test('backup_deleted lists again and backup_progress does not', () async {
    final controller = build();
    await controller.load(['USB2']);
    listed.clear();

    events.add(const FileEvent(kind: 'backup_progress', path: ''));
    expect(listed, isEmpty);

    onDrive['USB2']!.removeLast();
    events.add(
      const FileEvent(
        kind: 'backup_deleted',
        path: '',
        data: {'deviceSerial': 'USB2', 'run': '2026-10-26 09.00'},
      ),
    );
    await pumpEventQueue();

    expect(listed, ['USB2']);
    expect(controller.runsFor('USB2'), hasLength(1));
  });
}
