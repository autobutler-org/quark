import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/job.dart';

void main() {
  test('parses a finished job', () {
    final job = Job.fromJson({
      'id': 3,
      'kind': JobKinds.videoTranscode,
      'lane': 'copy',
      'name': 'Convert vacation.mkv to MOV',
      'status': 'completed',
      'progress': 1,
      'attempts': 2,
      'createdAt': '2026-09-14T10:00:00Z',
      'startedAt': '2026-09-14T10:00:05Z',
      'finishedAt': '2026-09-14T10:01:35Z',
      'error': '',
    });

    expect(job.id, 3);
    expect(job.kind, JobKinds.videoTranscode);
    expect(job.lane, 'copy');
    expect(job.name, 'Convert vacation.mkv to MOV');
    expect(job.status, JobStatus.completed);
    expect(job.progress, 1.0);
    expect(job.attempts, 2);
    expect(job.createdAt, DateTime.utc(2026, 9, 14, 10));
    expect(job.startedAt, DateTime.utc(2026, 9, 14, 10, 0, 5));
    expect(job.finishedAt, DateTime.utc(2026, 9, 14, 10, 1, 35));
  });

  test('a job that has not started has no timestamps', () {
    final job = Job.fromJson({
      'id': 1,
      'kind': JobKinds.videoTranscode,
      'status': 'pending',
      'createdAt': '2026-09-14T10:00:00Z',
      'startedAt': null,
      'finishedAt': null,
    });

    expect(job.startedAt, isNull);
    expect(job.finishedAt, isNull);
  });

  test('an unknown kind and status parse rather than throw', () {
    final job = Job.fromJson({
      'id': 4,
      'kind': 'backup',
      'status': 'paused',
      'createdAt': '2026-09-14T10:00:00Z',
    });

    expect(job.kind, 'backup');
    expect(job.status, JobStatus.unknown);
    // A Quark that predates the fields sends no attempts and no lane.
    expect(job.attempts, 0);
    expect(job.lane, isEmpty);
  });

  group('params', () {
    test('parses an object and keeps it unmodifiable', () {
      final job = Job.fromJson({
        'id': 5,
        'kind': JobKinds.videoTranscode,
        'status': 'pending',
        'createdAt': '2026-09-14T10:00:00Z',
        'params': {
          'relPath': 'videos/vacation.mkv',
          'serial': '',
          'format': 'mov',
          'quality': 'original',
        },
      });

      expect(job.params, {
        'relPath': 'videos/vacation.mkv',
        'serial': '',
        'format': 'mov',
        'quality': 'original',
      });
      expect(() => job.params['format'] = 'webm', throwsUnsupportedError);
    });

    test('is empty when missing', () {
      final job = Job.fromJson({'id': 6, 'status': 'pending'});

      expect(job.params, isEmpty);
    });

    test('is empty when not an object', () {
      final job = Job.fromJson({
        'id': 7,
        'status': 'pending',
        'params': '{"relPath":"x"}',
      });

      expect(job.params, isEmpty);
    });
  });

  group('detail', () {
    test('parses what a completed trim saved, unmodifiable', () {
      final job = Job.fromJson({
        'id': 8,
        'kind': JobKinds.videoTrim,
        'status': 'completed',
        'detail': {'relPath': 'videos/a_trimmed.mp4', 'actualStartMs': 1875},
      });

      expect(job.detail, {
        'relPath': 'videos/a_trimmed.mp4',
        'actualStartMs': 1875,
      });
      expect(() => job.detail['relPath'] = 'x', throwsUnsupportedError);
    });

    test('is empty when missing or not an object', () {
      expect(Job.fromJson({'id': 9, 'status': 'running'}).detail, isEmpty);
      expect(
        Job.fromJson({'id': 9, 'status': 'running', 'detail': 'x'}).detail,
        isEmpty,
      );
    });
  });

  test('a trim reports no progress; a conversion does', () {
    expect(
      Job.fromJson({'id': 1, 'kind': JobKinds.videoTrim}).reportsProgress,
      isFalse,
    );
    expect(
      Job.fromJson({'id': 2, 'kind': JobKinds.videoTranscode}).reportsProgress,
      isTrue,
    );
  });
}
