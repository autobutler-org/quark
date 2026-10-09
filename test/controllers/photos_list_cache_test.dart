import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/paginated_photos_response.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/utils/photo_grid_config.dart';

PhotoItem _photo(int i) => PhotoItem(
  relPath: 'camera/$i.jpg',
  fileName: '$i.jpg',
  size: 1,
  mtime: 0,
  serial: 'sd1',
);

void main() {
  var scope = 'quark-a';
  late PhotosListCache cache;

  CachedPhotoPage? peek({
    PhotoSortField sort = PhotoSortField.added,
    PhotoSortOrder order = PhotoSortOrder.desc,
  }) => cache.photos(sort: sort, order: order);

  void put(int count, {int? total}) => cache.putPhotos(
    [for (var i = 0; i < count; i++) _photo(i)],
    total: total ?? count,
    sort: PhotoSortField.added,
    order: PhotoSortOrder.desc,
  );

  setUp(() {
    scope = 'quark-a';
    cache = PhotosListCache(scope: () => scope);
  });

  test('has nothing to show before the first put', () {
    expect(peek(), isNull);
    expect(cache.favoriteKeys, isNull);
  });

  test('a put is shown by the next peek, with the Quark\'s total', () {
    put(3, total: 60);

    expect(peek()!.photos.map((p) => p.fileName), ['0.jpg', '1.jpg', '2.jpg']);
    expect(peek()!.total, 60);
  });

  test('a put replaces the one before it', () {
    put(3);
    put(1);

    expect(peek()!.photos, hasLength(1));
  });

  test('photos kept in one order are not shown under another', () {
    put(3);

    expect(peek(order: PhotoSortOrder.asc), isNull);
    expect(peek(sort: PhotoSortField.name), isNull);
    expect(peek(), isNotNull);
  });

  test('keeps no more than the cap, and still the whole total', () {
    put(PhotoGridConfig.maxCachedPhotos + 5);

    final page = peek()!;
    expect(page.photos, hasLength(PhotoGridConfig.maxCachedPhotos));
    expect(page.photos.first.fileName, '0.jpg');
    expect(page.total, PhotoGridConfig.maxCachedPhotos + 5);
  });

  test('favorites are replaced whole and updated one at a time', () {
    cache.putFavoriteKeys({'a', 'b'});
    cache.setFavorite('c', isFavorite: true);
    cache.setFavorite('a', isFavorite: false);

    expect(cache.favoriteKeys, {'b', 'c'});

    cache.putFavoriteKeys({'z'});
    expect(cache.favoriteKeys, {'z'});
  });

  test('a favorite toggled before any were listed is not a whole list', () {
    cache.setFavorite('a', isFavorite: true);

    expect(cache.favoriteKeys, isNull);
  });

  test('what it hands out cannot change what it holds', () {
    final keys = {'a'};
    cache.putFavoriteKeys(keys);
    keys.add('b');

    expect(cache.favoriteKeys, {'a'});
    expect(() => cache.favoriteKeys!.add('c'), throwsUnsupportedError);
  });

  test('another Quark or account never sees this one\'s photos', () {
    put(3);
    cache.putFavoriteKeys({'a'});
    scope = 'quark-b';

    expect(peek(), isNull);
    expect(cache.favoriteKeys, isNull);

    // And coming back does not bring them back: the other Quark may have
    // been used in between.
    scope = 'quark-a';
    expect(peek(), isNull);
  });

  test('clear forgets everything', () {
    put(3);
    cache.putFavoriteKeys({'a'});

    cache.clear();

    expect(peek(), isNull);
    expect(cache.favoriteKeys, isNull);
  });
}
