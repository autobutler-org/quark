import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';

PhotoAlbum _album(int id) => PhotoAlbum(
  id: id,
  name: 'Album $id',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  itemCount: 0,
);

PhotoAlbumItem _item(int albumId, int i) => PhotoAlbumItem(
  id: i,
  albumId: albumId,
  deviceSerial: 'sd1',
  relPath: 'camera/$i.jpg',
  addedAt: DateTime(2024),
);

void main() {
  var scope = 'quark-a';
  late AlbumsCache cache;

  List<PhotoAlbumItem>? peek(
    int albumId, {
    PhotoSortField sort = PhotoSortField.added,
    PhotoSortOrder order = PhotoSortOrder.desc,
  }) => cache.items(albumId, sort: sort, order: order);

  void put(int albumId, int count) => cache.putItems(
    albumId,
    [for (var i = 0; i < count; i++) _item(albumId, i)],
    sort: PhotoSortField.added,
    order: PhotoSortOrder.desc,
  );

  setUp(() {
    scope = 'quark-a';
    cache = AlbumsCache(scope: () => scope);
  });

  test('has nothing to show before the first put', () {
    expect(cache.albums, isNull);
    expect(peek(1), isNull);
  });

  test('a put is shown by the next peek', () {
    cache.putAlbums([_album(1), _album(2)]);
    put(1, 2);

    expect(cache.albums!.map((a) => a.id), [1, 2]);
    expect(peek(1)!.map((i) => i.relPath), ['camera/0.jpg', 'camera/1.jpg']);
  });

  test('a put replaces the one before it', () {
    cache.putAlbums([_album(1), _album(2)]);
    cache.putAlbums([_album(3)]);
    put(1, 3);
    put(1, 1);

    expect(cache.albums!.single.id, 3);
    expect(peek(1), hasLength(1));
  });

  test('each album keeps its own items', () {
    put(1, 1);
    put(2, 3);

    expect(peek(1), hasLength(1));
    expect(peek(2), hasLength(3));
    expect(peek(3), isNull);
  });

  test('items kept in one order are not shown under another', () {
    put(1, 3);

    expect(peek(1, order: PhotoSortOrder.asc), isNull);
    expect(peek(1, sort: PhotoSortField.name), isNull);
    expect(peek(1), isNotNull);
  });

  test('dropping the albums leaves every album\'s items', () {
    cache.putAlbums([_album(1)]);
    put(1, 1);

    cache.dropAlbums();

    expect(cache.albums, isNull);
    expect(peek(1), hasLength(1));
  });

  test('dropping one album\'s items leaves the rest', () {
    cache.putAlbums([_album(1), _album(2)]);
    put(1, 1);
    put(2, 1);

    cache.dropItems(1);

    expect(peek(1), isNull);
    expect(peek(2), hasLength(1));
    expect(cache.albums, hasLength(2));
  });

  test('dropping items with no album drops every album\'s', () {
    cache.putAlbums([_album(1), _album(2)]);
    put(1, 1);
    put(2, 1);

    cache.dropItems();

    expect(peek(1), isNull);
    expect(peek(2), isNull);
    expect(cache.albums, hasLength(2));
  });

  test('what it hands out cannot change what it holds', () {
    final albums = [_album(1)];
    final items = [_item(1, 0)];
    cache.putAlbums(albums);
    cache.putItems(
      1,
      items,
      sort: PhotoSortField.added,
      order: PhotoSortOrder.desc,
    );
    albums.add(_album(2));
    items.add(_item(1, 1));

    expect(cache.albums, hasLength(1));
    expect(peek(1), hasLength(1));
    expect(() => cache.albums!.add(_album(3)), throwsUnsupportedError);
    expect(() => peek(1)!.add(_item(1, 2)), throwsUnsupportedError);
  });

  test('another Quark or account never sees this one\'s albums', () {
    cache.putAlbums([_album(1)]);
    put(1, 1);
    scope = 'quark-b';

    expect(cache.albums, isNull);
    expect(peek(1), isNull);

    // And coming back does not bring them back: the other Quark may have
    // been used in between.
    scope = 'quark-a';
    expect(cache.albums, isNull);
    expect(peek(1), isNull);
  });

  test('clear forgets everything', () {
    cache.putAlbums([_album(1)]);
    put(1, 1);

    cache.clear();

    expect(cache.albums, isNull);
    expect(peek(1), isNull);
  });
}
