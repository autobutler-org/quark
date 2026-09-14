import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/utils/album_link.dart';

PhotoAlbum _album(
  int id,
  String name, {
  String? smartType,
  List<PhotoAlbum> children = const [],
}) => PhotoAlbum(
  id: id,
  name: name,
  smartType: smartType,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  itemCount: 0,
  children: children,
);

void main() {
  final tree = [
    _album(1, 'Favorites', smartType: 'favorites'),
    _album(2, 'Trips', children: [_album(3, 'Japan'), _album(4, 'Iceland')]),
    _album(5, 'Summer Trip'),
    _album(6, 'Pets'),
    _album(7, 'Pets'),
    _album(8, 'a/b'),
    _album(9, '2024'),
    _album(2024, 'Twenty twenty-four'),
  ];

  int? resolve(String value) => resolveAlbumLink(tree, value)?.id;

  group('albumLink', () {
    test('names a root album by its name', () {
      expect(albumLink(tree, 2), 'Trips');
      expect(albumLink(tree, 5), 'Summer Trip');
    });

    test('names a nested album by its path from the root', () {
      expect(albumLink(tree, 3), 'Trips/Japan');
    });

    test('names a system album by its name', () {
      expect(albumLink(tree, 1), 'Favorites');
    });

    test('falls back to the id for a duplicate name', () {
      expect(albumLink(tree, 6), '6');
      expect(albumLink(tree, 7), '7');
    });

    test('falls back to the id for a name containing a slash', () {
      expect(albumLink(tree, 8), '8');
    });

    test('names an album called a number by that name', () {
      expect(albumLink(tree, 9), '2024');
    });

    test('falls back to the id for an album not in the tree', () {
      expect(albumLink(tree, 42), '42');
    });

    test('every link reads back as its album', () {
      for (final id in [1, 2, 3, 4, 5, 6, 7, 8, 9]) {
        expect(resolve(albumLink(tree, id)), id, reason: 'album $id');
      }
    });
  });

  group('resolveAlbumLink', () {
    test('reads a root name and a nested path', () {
      expect(resolve('Trips'), 2);
      expect(resolve('Trips/Japan'), 3);
      expect(resolve('Summer Trip'), 5);
      expect(resolve('Favorites'), 1);
    });

    test('falls back to a case-insensitive match', () {
      expect(resolve('trips/JAPAN'), 3);
      expect(resolve('favorites'), 1);
    });

    test('an exact match wins over a case-insensitive one', () {
      final mixed = [_album(1, 'trips'), _album(2, 'Trips')];
      expect(resolveAlbumLink(mixed, 'Trips')?.id, 2);
      expect(resolveAlbumLink(mixed, 'TRIPS'), isNull, reason: 'ambiguous');
    });

    test('an ambiguous name matches nothing', () {
      expect(resolve('Pets'), isNull);
    });

    test('a name wins over the id it spells', () {
      expect(resolve('2024'), 9);
    });

    test('digits naming no album are read as an id', () {
      expect(resolve('3'), 3);
      expect(resolve('6'), 6);
      expect(resolveAlbumLink([_album(-2, 'Demo')], '-2')?.id, -2);
    });

    test('an unknown value matches nothing', () {
      expect(resolve('Nowhere'), isNull);
      expect(resolve('Trips/Nowhere'), isNull);
      expect(resolve('42'), isNull);
      expect(resolve(''), isNull);
    });
  });
}
