import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/models/job.dart';
import 'package:quark/router.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

Map<String, dynamic> _json(
  int id, {
  String status = 'running',
  String kind = JobKinds.videoTranscode,
  String lane = 'encode',
  String name = 'Convert vacation.mkv to MOV',
  Map<String, Object?> params = const {
    'relPath': 'videos/2024/vacation.mkv',
    'serial': 'USB 1',
    'format': 'mov',
    'quality': 'original',
  },
}) => {
  'id': id,
  'kind': kind,
  'lane': lane,
  'name': name,
  'params': params,
  'status': status,
  'progress': 0.5,
  'attempts': 1,
  'createdAt': '2026-09-14T10:00:00Z',
  'startedAt': status == 'pending' ? null : '2026-09-14T10:00:00Z',
  'finishedAt': switch (status) {
    'completed' || 'failed' || 'canceled' => '2026-09-14T10:01:30Z',
    _ => null,
  },
};

Job _job(int id, {String status = 'running', String lane = 'encode'}) =>
    Job.fromJson(_json(id, status: status, lane: lane));

void main() {
  late StreamController<FileEvent> events;
  late List<Job> served;
  late int listCalls;
  late ValueNotifier<String?> session;
  final built = <JobsController>[];

  JobsController build({
    Future<Job> Function(int id)? cancelJob,
    Future<void> Function(int id)? retryJob,
    Object? listError,
  }) {
    final controller = JobsController(
      listJobs: ({required kinds}) async {
        listCalls++;
        expect(kinds, JobKinds.all);
        if (listError != null) throw listError;
        return served;
      },
      cancelJob: cancelJob ?? (id) async => _job(id, status: 'canceled'),
      retryJob: retryJob ?? (id) async {},
      events: () => events.stream,
      session: () => session,
      clock: () => DateTime.utc(2026, 9, 14, 10, 0, 42),
    );
    built.add(controller);
    return controller;
  }

  setUp(() {
    events = StreamController<FileEvent>.broadcast();
    served = [];
    listCalls = 0;
    session = ValueNotifier(null);
  });

  tearDown(() async {
    for (final controller in built) {
      controller.dispose();
    }
    built.clear();
    await events.close();
  });

  test('maps loaded jobs into items and counts the running ones', () async {
    served = [
      _job(3, lane: 'copy'),
      _job(2, status: 'pending'),
      _job(1, status: 'failed'),
    ];
    final controller = build();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.load();

    expect(notifications, 2, reason: 'once to start loading, once when done');
    expect(controller.runningCount, 1);
    expect(controller.error, isNull);
    final items = controller.items;
    expect(items.map((i) => i.id), [3, 2, 1]);
    expect(items[0].status, JobItemStatus.running);
    expect(items[0].isQuickCopy, isTrue);
    expect(items[0].elapsed, const Duration(seconds: 42), reason: 'live');
    expect(items[0].canCancel, isTrue);
    expect(items[1].canCancel, isTrue);
    expect(items[1].elapsed, isNull);
    expect(items[2].canCancel, isFalse);
    expect(items[2].canRetry, isTrue);
    expect(items[2].elapsed, const Duration(seconds: 90), reason: 'fixed');
  });

  test('loads on sign-in and forgets the jobs on sign-out', () async {
    served = [_job(1)];
    session.value = 'token';
    final controller = build()..start();
    await pumpEventQueue();
    expect(listCalls, 1, reason: 'already signed in at start');
    expect(controller.runningCount, 1);

    session.value = null;
    expect(controller.jobs, isEmpty);
    expect(controller.runningCount, 0);

    session.value = 'other';
    await pumpEventQueue();
    expect(listCalls, 2);
    expect(controller.runningCount, 1);
  });

  test('a failed load carries copy from Errors', () async {
    final controller = build(listError: const ApiException(500));
    await controller.load();
    expect(controller.error, Errors.message(const ApiException(500), 'x'));
    expect(controller.isLoading, isFalse);
  });

  test('applies queued and progress events without fetching again', () async {
    served = [_job(1, status: 'pending')];
    final controller = build()..start();
    await controller.load();

    events
      ..add(FileEvent(kind: 'job_queued', path: '', data: _json(2)))
      ..add(FileEvent(kind: 'job_started', path: '', data: _json(1)))
      ..add(const FileEvent(kind: 'upload', path: 'a.txt'))
      ..add(
        FileEvent(
          kind: 'job_queued',
          path: '',
          data: _json(9, kind: 'backup'),
        ),
      );
    await pumpEventQueue();

    expect(controller.jobs.map((j) => j.id), [2, 1]);
    expect(controller.runningCount, 2);
    expect(listCalls, 1, reason: 'only the initial load');
  });

  test('fetches the list again on every terminal event', () async {
    served = [_job(1)];
    final controller = build()..start();
    await controller.load();

    served = [_job(1, status: 'completed')];
    for (final status in ['completed', 'failed', 'canceled']) {
      events.add(
        FileEvent(
          kind: 'job_$status',
          path: '',
          data: _json(1, status: status),
        ),
      );
    }
    await pumpEventQueue();

    expect(listCalls, 4);
    expect(controller.runningCount, 0);
  });

  test('fetches the list again when access or an account changes', () async {
    served = [_job(1)];
    final controller = build()..start();
    await controller.load();

    served = [];
    events
      ..add(const FileEvent(kind: 'access_changed', path: 'shared'))
      ..add(const FileEvent(kind: 'account_changed', path: ''));
    await pumpEventQueue();

    expect(listCalls, 3);
    expect(controller.jobs, isEmpty);
  });

  test('cancel applies the returned job, or maps a refusal', () async {
    served = [_job(1)];
    final controller = build()..start();
    await controller.load();

    expect(await controller.cancel(1), isNull);
    expect(controller.jobs.single.status, JobStatus.canceled);

    final refusing = build(cancelJob: (_) => throw const ApiException(409));
    expect(await refusing.cancel(1), 'That job has already finished.');
  });

  test('retry fetches the list again, or maps a refusal', () async {
    final controller = build();
    expect(await controller.retry(1), isNull);
    expect(listCalls, 1);

    final refusing = build(retryJob: (_) => throw const ApiException(422));
    expect(await refusing.retry(1), Errors.retryJob(const ApiException(422)));
  });

  group('announcementFor', () {
    test('a completed conversion shows the folder on its device', () {
      final a = JobsController.announcementFor(
        Job.fromJson(_json(1, status: 'completed')),
      )!;
      expect(a.message, 'Converted vacation.mkv to MOV');
      expect(a.actionLabel, 'Show');
      expect(a.route, '/files/videos/2024?serial=USB+1');
    });

    test('a conversion at the root on internal storage shows /files', () {
      final a = JobsController.announcementFor(
        Job.fromJson(
          _json(
            1,
            status: 'completed',
            params: {'relPath': 'clip.avi', 'serial': '', 'format': 'mp4'},
          ),
        ),
      )!;
      expect(a.route, AppRoutes.files);
    });

    test('a failed job gets Errors copy and a link to the jobs page', () {
      final a = JobsController.announcementFor(
        Job.fromJson(_json(1, status: 'failed')),
      )!;
      expect(a.message, "Couldn't convert vacation.mkv to MOV.");
      expect(a.actionLabel, 'View');
      expect(a.route, AppRoutes.jobs);
    });

    test('an unknown kind falls back to its name with no Show', () {
      final done = JobsController.announcementFor(
        Job.fromJson(
          _json(1, status: 'completed', kind: 'backup', name: 'Back up'),
        ),
      )!;
      expect(done.message, 'Back up');
      expect(done.route, isNull);

      final failed = JobsController.announcementFor(
        Job.fromJson(
          _json(1, status: 'failed', kind: 'backup', name: 'Back up'),
        ),
      )!;
      expect(failed.message, "Back up didn't finish.");
      expect(failed.route, AppRoutes.jobs);
    });

    test('nothing to say for a job that did not complete or fail', () {
      for (final status in ['pending', 'running', 'canceled']) {
        expect(
          JobsController.announcementFor(
            Job.fromJson(_json(1, status: status)),
          ),
          isNull,
        );
      }
    });

    test('terminal events are announced app-wide', () async {
      final controller = build()..start();
      final said = <String>[];
      controller.announcements.listen((a) => said.add(a.message));

      events
        ..add(FileEvent(kind: 'job_progress', path: '', data: _json(1)))
        ..add(
          FileEvent(
            kind: 'job_completed',
            path: '',
            data: _json(1, status: 'completed'),
          ),
        );
      await pumpEventQueue();

      expect(said, ['Converted vacation.mkv to MOV']);
    });
  });
}
