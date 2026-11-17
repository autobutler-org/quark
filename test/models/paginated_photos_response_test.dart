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
}
