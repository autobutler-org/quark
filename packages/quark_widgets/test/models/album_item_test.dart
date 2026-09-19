import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  test('compares by value, children included', () {
    const a = AlbumItem(
      id: 1,
      name: 'Trips',
      children: [AlbumItem(id: 2, name: 'Iceland')],
    );
    const same = AlbumItem(
      id: 1,
      name: 'Trips',
      children: [AlbumItem(id: 2, name: 'Iceland')],
    );
    const differentChild = AlbumItem(
      id: 1,
      name: 'Trips',
      children: [AlbumItem(id: 2, name: 'Japan')],
    );

    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(differentChild));
  });

  test('defaults to a childless, user-owned, empty album', () {
    const item = AlbumItem(id: 1, name: 'Trips');

    expect(item.children, isEmpty);
    expect(item.itemCount, 0);
    expect(item.isSystem, isFalse);
    expect(item.isFavorites, isFalse);
    expect(item.parentId, isNull);
  });

  /// #2061: the album sheets rendered "1 photos".
  group('photoCountLabel', () {
    test('an album holding one photo says photo, not photos', () {
      expect(
        const AlbumItem(id: 1, name: 'Trips', itemCount: 1).photoCountLabel,
        '1 photo',
      );
    });

    test('every other count is plural, empty included', () {
      expect(const AlbumItem(id: 1, name: 'Trips').photoCountLabel, '0 photos');
      expect(
        const AlbumItem(id: 1, name: 'Trips', itemCount: 2).photoCountLabel,
        '2 photos',
      );
    });
  });
}
