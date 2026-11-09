import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/data_protection_controller.dart';
import 'package:quark/services/data_protection_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

DataProtectionStatus _status({
  String level = 'protected',
  String sentence =
      'Your files are on 3 drives. Keep one backup drive somewhere else.',
  DataProtectionAction action = DataProtectionAction.keepElsewhere,
  List<DataProtectionDataDrive> dataDrives = const [],
  List<DataProtectionBackupDrive> backupDrives = const [],
}) {
  return DataProtectionStatus(
    level: level,
    sentence: sentence,
    action: action,
    dataDrives: dataDrives,
    backupDrives: backupDrives,
  );
}

/// The protection card's controller. The level is the one the fake Quark
/// reported; a drive list that disagrees does not change it. Back up now
/// starts onto each connected backup drive.
void main() {
  test('loads the reported level and does not recount the drives', () async {
    final controller = DataProtectionController(
      fetch: () async => _status(
        dataDrives: const [
          DataProtectionDataDrive(serial: '', name: 'Built-in', level: 'basic'),
        ],
      ),
      events: const Stream.empty(),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.level, DataProtectionLevel.protected);
    expect(controller.status!.dataDrive('')!.level, 'basic');
    expect(controller.error, isNull);
    expect(controller.isLoading, isFalse);
  });

  test('a failed first load keeps the card empty', () async {
    final controller = DataProtectionController(
      fetch: () async => throw const ApiException(500, 'check the backup'),
      events: const Stream.empty(),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.status, isNull);
    expect(controller.level, isNull);
    expect(controller.error, isA<ApiException>());
    expect(controller.isLoading, isFalse);
  });

  test('a failed refresh keeps the level already shown', () async {
    var fail = false;
    final controller = DataProtectionController(
      fetch: () async {
        if (fail) throw const ApiException(500, 'check the backup');
        return _status(
          level: 'basic',
          action: DataProtectionAction.startBackup,
        );
      },
      events: const Stream.empty(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    fail = true;
    await controller.load();

    expect(controller.level, DataProtectionLevel.basic);
    expect(controller.error, isA<ApiException>());
    expect(controller.isLoading, isFalse);
  });

  test('a slow first load does not overwrite a newer one', () async {
    final first = Completer<DataProtectionStatus>();
    final second = Completer<DataProtectionStatus>();
    var calls = 0;
    final controller = DataProtectionController(
      fetch: () {
        calls++;
        return calls == 1 ? first.future : second.future;
      },
      events: const Stream.empty(),
    );
    addTearDown(controller.dispose);

    final older = controller.load();
    final newer = controller.load();
    second.complete(_status(level: 'protected'));
    await newer;
    first.complete(_status(level: 'unprotected'));
    await older;

    expect(controller.level, DataProtectionLevel.protected);
  });

  test(
    'backup_completed and backup_deleted load again, backup_progress does not',
    () async {
      var calls = 0;
      final events = StreamController<FileEvent>.broadcast(sync: true);
      addTearDown(events.close);
      final controller = DataProtectionController(
        fetch: () async {
          calls++;
          return _status(level: calls == 1 ? 'basic' : 'protected');
        },
        events: events.stream,
      );
      addTearDown(controller.dispose);

      await controller.load();
      events.add(const FileEvent(kind: 'backup_progress', path: ''));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);

      events.add(const FileEvent(kind: 'backup_completed', path: ''));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(controller.level, DataProtectionLevel.protected);

      events.add(const FileEvent(kind: 'backup_failed', path: ''));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 3);

      // A run deleted by hand or pruned elsewhere (#4044).
      events.add(const FileEvent(kind: 'backup_deleted', path: ''));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 4);
    },
  );

  test('dispose during an in-flight load does not throw', () async {
    final gate = Completer<DataProtectionStatus>();
    final controller = DataProtectionController(
      fetch: () => gate.future,
      events: const Stream.empty(),
    );

    final pending = controller.load();
    controller.dispose();
    gate.complete(_status());
    await pending;
  });

  test('fromJson reads data drives and backup drives', () {
    final status = DataProtectionStatus.fromJson({
      'level': 'basic',
      'sentence': 'Every drive has a copy on one backup drive.',
      'nextStep': 'start-backup',
      'dataDrives': [
        {
          'serial': '',
          'name': 'Built-in storage',
          'level': 'basic',
          'copies': [
            {
              'backupSerial': 'usb-1',
              'backupName': 'Backup A',
              'copiedAt': '2026-11-02T15:04:05Z',
              'counts': true,
              'reason': '',
            },
            {
              'backupSerial': 'usb-2',
              'backupName': 'Office',
              'copiedAt': '2026-09-01T00:00:00Z',
              'counts': false,
              'reason': 'This copy is more than 30 days old.',
            },
          ],
        },
      ],
      'backupDrives': [
        {
          'serial': 'usb-1',
          'name': 'Backup A',
          'state': 'current',
          'holds': [
            {
              'serial': '',
              'name': 'Built-in storage',
              'copiedAt': '2026-11-02T15:04:05Z',
            },
          ],
          'newestCopy': '2026-11-02T15:04:05Z',
        },
        {
          'serial': 'usb-3',
          'name': 'Fresh',
          'state': 'no-copies',
          'holds': [],
          'newestCopy': null,
        },
      ],
    });

    expect(status.action, DataProtectionAction.startBackup);
    final builtIn = status.dataDrive('')!;
    expect(builtIn.copies, hasLength(2));
    expect(builtIn.copies.first.reason, isNull);
    expect(builtIn.copies.first.copiedAt, DateTime.utc(2026, 11, 2, 15, 4, 5));
    expect(builtIn.copies.last.counts, isFalse);
    expect(builtIn.copies.last.reason, 'This copy is more than 30 days old.');
    final backup = status.backupDrive('usb-1')!;
    expect(backup.state, DataProtectionBackupState.current);
    expect(backup.holds.single.name, 'Built-in storage');
    expect(backup.newestCopy, DateTime.utc(2026, 11, 2, 15, 4, 5));
    expect(status.backupDrive('usb-3')!.newestCopy, isNull);
    expect(status.backupDrive('nope'), isNull);

    for (final bad in [
      {'level': 'superb'},
      {
        'level': 'basic',
        'backupDrives': [
          {'serial': 'x', 'name': 'X', 'state': 'lost'},
        ],
      },
    ]) {
      expect(
        () => DataProtectionStatus.fromJson({
          'sentence': 'nope',
          'nextStep': 'start-backup',
          ...bad,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Invalid protection status',
          ),
        ),
      );
    }
  });

  test('Back up now starts onto each connected drive not receiving', () async {
    final started = <String>[];
    final controller = DataProtectionController(
      fetch: () async => _status(
        backupDrives: [
          for (final state in DataProtectionBackupState.values)
            DataProtectionBackupDrive(
              serial: state.wire,
              name: state.wire,
              state: state,
            ),
        ],
      ),
      startBackup:
          ({required targetDeviceSerial, acknowledgeHealth = false}) async {
            started.add(targetDeviceSerial);
            if (targetDeviceSerial == 'current') {
              throw const ApiException(409, 'start the backup');
            }
            return 'job';
          },
      events: const Stream.empty(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final error = await controller.backUpNow();

    expect(started, ['no-copies', 'current', 'behind']);
    expect(error, isA<ApiException>());
  });
}
