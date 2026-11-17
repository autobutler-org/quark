import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_sort.dart';

/// #4217: the grid names each Quark photo's thumbnail version in `v`, from the
/// listing's mtime and rotation, so the thumbnail is cached as immutable and a
/// rotation is a new URL.
void main() {
  PhotosController controller(List<wire.PhotoItem> photos) => PhotosController(
    isWeb: true,
    activeHost: () => 'quark.local',
    listCache: PhotosListCache(scope: () => 'test'),
    albumsCache: AlbumsCache(scope: () => 'test'),
    listAlbums: ({bool tree = false}) async => [],
    listFavoriteKeys: () async => <String>{},
    getPhotos:
        ({
          int offset = 0,
          int limit = 50,
          String? serial,
          PhotoSortField sort = PhotoSortField.added,
          PhotoSortOrder order = PhotoSortOrder.desc,
          String? q,
        }) async => wire.PaginatedPhotosResponse(
          photos: offset == 0 ? photos : const [],
          total: photos.length,
          offset: offset,
          limit: limit,
        ),
    thumbnailUrl: (path, {String? serial, String? size}) =>
        Uri.parse('https://quark.local/thumb/$path?serial=$serial'),
  );

  test('the thumbnail URL carries mtime.rotation in v', () async {
    final c = controller(const [
      wire.PhotoItem(
        relPath: 'camera/a.jpg',
        fileName: 'a.jpg',
        size: 1,
        mtime: 1700000000,
        serial: 'sd1',
      ),
      wire.PhotoItem(
        relPath: 'camera/b.jpg',
        fileName: 'b.jpg',
        size: 1,
        mtime: 1700000001,
        serial: 'sd1',
        rotationQuarters: 3,
      ),
    ]);
    await c.refresh();

    expect(
      c.thumbnailUrl('sd1:camera/a.jpg'),
      Uri.parse(
        'https://quark.local/thumb/camera/a.jpg?serial=sd1&v=1700000000.0',
      ),
    );
    expect(
      c.thumbnailUrl('sd1:camera/b.jpg')?.queryParameters['v'],
      '1700000001.3',
    );
  });

  test('a photo with no mtime keeps an unversioned URL', () async {
    final c = controller(const [
      wire.PhotoItem(
        relPath: 'camera/a.jpg',
        fileName: 'a.jpg',
        size: 1,
        mtime: 0,
        serial: 'sd1',
      ),
    ]);
    await c.refresh();

    expect(
      c.thumbnailUrl('sd1:camera/a.jpg')?.queryParameters.containsKey('v'),
      isFalse,
    );
  });
}
