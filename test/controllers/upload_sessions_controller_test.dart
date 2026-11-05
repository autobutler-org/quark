import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/upload_sessions_controller.dart';
import 'package:quark/models/upload_session_summary.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

UploadSessionSummary _session(
  String id, {
  UploadSessionState state = UploadSessionState.uploading,
  int offset = 0,
  int total = 100,
  DateTime? updatedAt,
  String rootDir = '',
  String serial = '',
}) => UploadSessionSummary(
  sessionId: id,
  fileName: '$id.zip',
  rootDir: rootDir,
  serial: serial,
  state: state,
  totalSize: total,
  offset: offset,
  createdAt: DateTime.utc(2026, 11, 4, 12),
  updatedAt: updatedAt ?? DateTime.utc(2026, 11, 4, 12),
);

void main() {
  late StreamController<FileEvent> events;
  late UploadSessionList served;
  late int listCalls;
  late ValueNotifier<String?> session;
  late DateTime now;
  final built = <UploadSessionsController>[];

  UploadSessionsController build({
    Future<void> Function(String id)? cancelSession,
    Object? listError,
  }) {
    final controller = UploadSessionsController(
      listSessions: () async {
        listCalls++;
        if (listError != null) throw listError;
        return served;
      },
      cancelSession: cancelSession ?? (id) async {},
      events: () => events.stream,
      session: () => session,
      clock: () => now,
      refetchDelay: Duration.zero,
    );
    built.add(controller);
    return controller;
  }

  setUp(() {
    events = StreamController<FileEvent>.broadcast();
    served = const UploadSessionList();
    listCalls = 0;
    session = ValueNotifier('token');
    now = DateTime.utc(2026, 11, 4, 12, 0, 10);
  });

  tearDown(() async {
    for (final c in built) {
      c.dispose();
    }
    built.clear();
    await events.close();
  });

  test('maps in-flight and ended sessions to upload items', () async {
    served = UploadSessionList(
      active: [
        _session(
          'a',
          offset: 40,
          updatedAt: DateTime.utc(2026, 11, 4, 12, 0, 9),
        ),
        _session('b', state: UploadSessionState.committing, offset: 100),
      ],
      finished: [
        _session('c', state: UploadSessionState.completed, offset: 100),
        _session('d', state: UploadSessionState.canceled),
        _session('e', state: UploadSessionState.failed),
        _session('f', state: UploadSessionState.expired),
      ],
    );
    final controller = build();
    await controller.load();

    expect(controller.activeCount, 2);
    expect(controller.items.map((i) => i.status), [
      UploadItemStatus.uploading,
      UploadItemStatus.finishing,
      UploadItemStatus.completed,
      UploadItemStatus.canceled,
      UploadItemStatus.failed,
      UploadItemStatus.expired,
    ]);
    final first = controller.items.first;
    expect(first.sentBytes, 40);
    expect(first.totalBytes, 100);
    expect(first.canCancel, isTrue);
    // A commit is already moving the file; it cannot be canceled.
    expect(controller.items[1].canCancel, isFalse);
    expect(controller.items[2].canCancel, isFalse);
  });

  test('works out the rate and time left from two readings', () async {
    final controller = build();
    served = UploadSessionList(
      active: [
        _session(
          'a',
          offset: 10,
          total: 110,
          updatedAt: DateTime.utc(2026, 11, 4, 12, 0, 0),
        ),
      ],
    );
    await controller.load();
    expect(controller.items.single.bytesPerSecond, isNull);

    served = UploadSessionList(
      active: [
        _session(
          'a',
          offset: 30,
          total: 110,
          updatedAt: DateTime.utc(2026, 11, 4, 12, 0, 2),
        ),
      ],
    );
    await controller.load();
    final item = controller.items.single;
    expect(item.bytesPerSecond, 10);
    expect(item.remaining, const Duration(seconds: 8));
  });

  test('calls an upload stalled when nothing has landed for a while', () async {
    served = UploadSessionList(
      active: [
        _session('a', offset: 10, updatedAt: DateTime.utc(2026, 11, 4, 12)),
      ],
    );
    now = DateTime.utc(2026, 11, 4, 12, 1);
    final controller = build();
    await controller.load();
    expect(controller.items.single.status, UploadItemStatus.stalled);
  });

  test(
    'fetches again on upload_session_changed and resync, not on others',
    () async {
      final controller = build()..start();
      await pumpEventQueue();
      final initial = listCalls;

      events.add(const FileEvent(kind: 'upload_session_changed', path: ''));
      await pumpEventQueue();
      expect(listCalls, initial + 1);

      events.add(const FileEvent(kind: 'resync', path: ''));
      await pumpEventQueue();
      expect(listCalls, initial + 2);

      events.add(const FileEvent(kind: 'upload', path: '/x'));
      await pumpEventQueue();
      expect(listCalls, initial + 2);
      expect(controller.error, isNull);
    },
  );

  test('collapses a burst of events into one fetch', () async {
    final controller = UploadSessionsController(
      listSessions: () async {
        listCalls++;
        return served;
      },
      cancelSession: (id) async {},
      events: () => events.stream,
      session: () => session,
      clock: () => now,
      refetchDelay: const Duration(milliseconds: 50),
    )..start();
    built.add(controller);
    await pumpEventQueue();
    final initial = listCalls;
    for (var i = 0; i < 5; i++) {
      events.add(const FileEvent(kind: 'upload_session_changed', path: ''));
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(listCalls, initial + 1);
  });

  test('signing out forgets the uploads', () async {
    served = UploadSessionList(active: [_session('a')]);
    final controller = build()..start();
    await pumpEventQueue();
    expect(controller.activeCount, 1);

    session.value = null;
    expect(controller.activeCount, 0);
    expect(controller.items, isEmpty);
  });

  test('a failed fetch lands in error with copy from Errors', () async {
    final controller = build(listError: const ApiException(500, 'boom'));
    await controller.load();
    expect(
      controller.error,
      Errors.message(const ApiException(500, 'boom'), 'load your uploads'),
    );
  });

  test('cancel calls the service and reloads, and reports a refusal', () async {
    final canceled = <String>[];
    final controller = build(cancelSession: (id) async => canceled.add(id));
    expect(await controller.cancel('a'), isNull);
    expect(canceled, ['a']);
    expect(listCalls, 1);

    final refusing = build(
      cancelSession: (id) async => throw const ApiException(404, 'gone'),
    );
    expect(
      await refusing.cancel('a'),
      Errors.cancelUpload(const ApiException(404, 'gone')),
    );
  });

  test('names the destination folder and an external drive', () {
    expect(
      UploadSessionsController.destinationLabel(_session('a')),
      'To Files',
    );
    expect(
      UploadSessionsController.destinationLabel(
        _session('a', rootDir: 'Google Drive/Taxes', serial: 'USB1'),
      ),
      'To Google Drive/Taxes on an external drive',
    );
  });
}
