import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/thumbnail_version.dart';

/// #4217: the client writes the version the Quark compares `v` against.
void main() {
  test('the version is the mtime and rotation joined by a dot', () {
    expect(thumbnailVersion(1700000000, 0), '1700000000.0');
    expect(thumbnailVersion(1700000000, 3), '1700000000.3');
  });

  test('an unknown mtime leaves the thumbnail unversioned', () {
    expect(thumbnailVersion(0, 1), isNull);
  });

  test('withThumbnailVersion sets v and keeps the rest', () {
    final url = Uri.parse('https://q.local/api/v0/thumbnails/a.jpg?serial=s1');
    final versioned = withThumbnailVersion(url, '5.1');
    expect(versioned.queryParameters, {'serial': 's1', 'v': '5.1'});
    expect(withThumbnailVersion(url, null), same(url));
  });
}
