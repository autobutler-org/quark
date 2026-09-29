import 'package:flutter_test/flutter_test.dart';
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
}
