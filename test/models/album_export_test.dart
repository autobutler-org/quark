import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/album_export.dart';
import 'package:quark/models/job.dart';

void main() {
  test('photo-export is a job kind the app lists', () {
    expect(JobKinds.photoExport, 'photo-export');
    expect(JobKinds.all, contains(JobKinds.photoExport));
  });

  test('reads a queued export', () {
    final queued = QueuedAlbumExport.fromJson({
      'jobId': 7,
      'deviceSerial': 'usb1',
      'relPath': 'Exports/Holiday',
    });
    expect(queued.jobId, 7);
    expect(queued.deviceSerial, 'usb1');
    expect(queued.relPath, 'Exports/Holiday');
  });

  test('reads a partial export with its failures', () {
    final summary = AlbumExportSummary.fromJson({
      'jobId': 7,
      'status': 'failed',
      'deviceSerial': '',
      'relPath': 'Exports/Holiday',
      'copied': 40,
      'failures': [
        {'name': 'beach.jpg', 'path': 'Holiday/beach.jpg', 'reason': 'missing'},
        {
          'name': 'cake.jpg',
          'path': 'Holiday/cake.jpg',
          'reason': 'not copied',
        },
        {'name': 'odd.jpg', 'path': 'Holiday/odd.jpg', 'reason': 'whatever'},
      ],
      'moreFailures': 2,
    });
    expect(summary.status, JobStatus.failed);
    expect(summary.copied, 40);
    expect(summary.failures.map((f) => f.name), [
      'beach.jpg',
      'cake.jpg',
      'odd.jpg',
    ]);
    expect(summary.failures.map((f) => f.reason), [
      AlbumExportFailureReason.missing,
      AlbumExportFailureReason.notCopied,
      AlbumExportFailureReason.notCopied,
    ]);
    expect(summary.failedCount, 5);
    expect(summary.isComplete, isFalse);
  });

  test('only a completed export with no failures is complete', () {
    AlbumExportSummary read(String status, {List<Object>? failures}) =>
        AlbumExportSummary.fromJson({
          'jobId': 1,
          'status': status,
          'relPath': 'x',
          'copied': 3,
          'failures': ?failures,
        });
    expect(read('completed').isComplete, isTrue);
    expect(read('completed').failures, isEmpty);
    expect(read('running').isComplete, isFalse);
    expect(read('later-status').status, JobStatus.unknown);
    expect(
      read(
        'completed',
        failures: [
          {'name': 'a.jpg', 'path': 'a.jpg', 'reason': 'missing'},
        ],
      ).isComplete,
      isFalse,
    );
  });
}
