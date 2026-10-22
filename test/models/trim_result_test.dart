import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/job.dart';
import 'package:quark/models/trim_result.dart';

void main() {
  test('reads the saved path and actual start', () {
    final result = TrimResult.fromJson({
      'relPath': 'videos/clip_trim.mp4',
      'actualStartMs': 1500,
    });

    expect(result.relPath, 'videos/clip_trim.mp4');
    expect(result.actualStart, const Duration(milliseconds: 1500));
  });

  test('treats a missing actual start as the beginning', () {
    final result = TrimResult.fromJson({'relPath': 'clip.mp4'});

    expect(result.actualStart, Duration.zero);
  });

  test('names only the file when the start shows as the same time', () {
    const result = TrimResult(
      relPath: 'videos/clip_trim.mp4',
      actualStart: Duration(seconds: 1),
    );

    expect(
      result.savedMessage(const Duration(milliseconds: 1969)),
      'Clip saved as clip_trim.mp4.',
    );
  });

  test('says where the clip starts when it moved to an earlier time', () {
    const result = TrimResult(
      relPath: 'videos/clip_trim.mp4',
      actualStart: Duration.zero,
    );

    expect(
      result.savedMessage(const Duration(milliseconds: 1200)),
      'Clip saved as clip_trim.mp4. '
      'It starts at 0:00 instead of 0:01, the closest point this video '
      'can be cut.',
    );
  });

  group('fromJob', () {
    Job trimJob({
      String kind = JobKinds.videoTrim,
      String status = 'completed',
      Map<String, Object?> detail = const {
        'relPath': 'videos/clip_trimmed.mp4',
        'actualStartMs': 3000,
      },
    }) => Job.fromJson({
      'id': 1,
      'kind': kind,
      'status': status,
      'params': {'relPath': 'videos/clip.mp4', 'startMs': 1800, 'endMs': 3500},
      'detail': detail,
    });

    test(
      'reads the result a completed trim saved, and its requested start',
      () {
        final job = trimJob();
        final result = TrimResult.fromJob(job)!;

        expect(result.relPath, 'videos/clip_trimmed.mp4');
        expect(result.actualStart, const Duration(seconds: 3));
        expect(
          TrimResult.requestedStart(job),
          const Duration(milliseconds: 1800),
        );
      },
    );

    test('is null for a trim that has not completed or saved nothing', () {
      expect(TrimResult.fromJob(trimJob(status: 'running')), isNull);
      expect(TrimResult.fromJob(trimJob(detail: const {})), isNull);
      expect(
        TrimResult.fromJob(trimJob(kind: JobKinds.videoTranscode)),
        isNull,
      );
    });
  });
}
