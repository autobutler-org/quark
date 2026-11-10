import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/backup_schedule_controller.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';

/// #3984: each backup drive's schedule, saving one, and reading them again
/// when a schedule changes anywhere. The Quark is a fake.
void main() {
  late Map<String, BackupSchedule> onQuark;
  late List<String> read;
  late StreamController<FileEvent> events;

  BackupScheduleController build() {
    final controller = BackupScheduleController(
      get: (serial) async {
        read.add(serial);
        return onQuark[serial] ?? const BackupSchedule();
      },
      set:
          ({
            required String deviceSerial,
            required BackupCadence cadence,
            required List<String> sourceSerials,
          }) async => onQuark[deviceSerial] = BackupSchedule(
            cadence: cadence,
            sourceSerials: sourceSerials,
            jobId: '9',
          ),
      events: events.stream,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    onQuark = {};
    read = [];
    events = StreamController<FileEvent>.broadcast(sync: true);
    addTearDown(events.close);
  });

  test('saving keeps the answer and returns its job', () async {
    final controller = build();
    await controller.load(['USB2']);

    final saved = await controller.save(
      deviceSerial: 'USB2',
      cadence: BackupCadence.weekly,
      sourceSerials: const [],
    );

    expect(saved.jobId, '9');
    expect(controller.scheduleFor('USB2')?.cadence, BackupCadence.weekly);
  });

  test('a schedule changed elsewhere is read again', () async {
    final controller = build();
    await controller.load(['USB2']);
    expect(controller.scheduleFor('USB2')?.cadence, BackupCadence.off);

    onQuark['USB2'] = const BackupSchedule(cadence: BackupCadence.daily);
    events.add(const FileEvent(kind: 'backup_schedule_changed', path: ''));
    await pumpEventQueue();

    expect(read, ['USB2', 'USB2']);
    expect(controller.scheduleFor('USB2')?.cadence, BackupCadence.daily);
  });
}
