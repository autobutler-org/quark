import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/paginated_photos_response.dart';

void main() {
  test('a photo carries its saved rotation, 0 when the Quark sends none', () {
    final page = PaginatedPhotosResponse.fromJson({
      'photos': [
        {'relPath': 'a.jpg', 'fileName': 'a.jpg', 'mtime': 5},
        {
          'relPath': 'b.jpg',
          'fileName': 'b.jpg',
          'mtime': 6,
          'rotationQuarters': 2,
        },
      ],
      'total': 2,
    });
    expect(page.photos.map((p) => p.rotationQuarters), [0, 2]);
  });

  test('a video carries isVideo and its length; a photo carries neither '
      '(#3428)', () {
    final page = PaginatedPhotosResponse.fromJson({
      'photos': [
        {'relPath': 'a.jpg', 'fileName': 'a.jpg'},
        {
          'relPath': 'clip.mp4',
          'fileName': 'clip.mp4',
          'isVideo': true,
          'durationMs': 42500,
        },
        {'relPath': 'odd.mkv', 'fileName': 'odd.mkv', 'isVideo': true},
      ],
      'total': 3,
    });
    expect(page.photos.map((p) => p.isVideo), [false, true, true]);
    expect(page.photos.map((p) => p.duration), [
      null,
      const Duration(milliseconds: 42500),
      null,
    ]);
  });
}
