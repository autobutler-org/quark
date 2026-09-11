import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:quark/controllers/photo_bytes_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_album.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

wire.PhotoItem _wirePhoto(int i, {String serial = 'sd1'}) => wire.PhotoItem(
  relPath: 'camera/$i.jpg',
  fileName: '$i.jpg',
  size: 1,
  mtime: 0,
  serial: serial,
  hasLiveVideo: i == 0,
);

PhotoAlbum _album(int id, String name, {String? smartType}) => PhotoAlbum(
  id: id,
  name: name,
  smartType: smartType,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  itemCount: 0,
);

StorageDevice _device(String serial, {bool enabled = true}) => StorageDevice(
  name: serial,
  devicePath: '/dev/$serial',
  mountPoint: '/mnt/$serial',
  fileSystem: 'ext4',
  totalBytes: 1,
  usedBytes: 0,
  availableBytes: 1,
  isInternal: false,
  isEnabled: enabled,
  serial: serial,
);

/// A Quark with [total] photos, served [PhotosController.pageSize] at a time,
/// and one device photo. Every call is recorded in [calls].
class _FakeQuark {
  _FakeQuark({this.total = 3});

  int total;
  String? host = 'https://quark.local';
  Object? photosError;
  Object? favoriteError;
  Set<String> favorites = {};
  List<PhotoAlbum> albums = [
    _album(1, 'Trips'),
    _album(2, 'Inbox', smartType: 'inbox'),
    _album(3, 'Favorites', smartType: 'favorites'),
  ];
  final Set<String> failingAdds = {};
  final List<String> calls = [];

  PhotosController controller() => PhotosController(
    isWeb: false,
    activeHost: () => host,
    getPhotos: ({int offset = 0, int limit = 50, String? serial}) async {
      calls.add('getPhotos($offset)');
      final error = photosError;
      if (error != null) throw error;
      final end = (offset + limit).clamp(0, total);
      return wire.PaginatedPhotosResponse(
        photos: [for (var i = offset; i < end; i++) _wirePhoto(i)],
        total: total,
        offset: offset,
        limit: limit,
      );
    },
    loadDeviceAssets: () async => [
      AssetEntity(id: 'dev1', typeInt: 1, width: 1, height: 1),
    ],
    listFavoriteKeys: () async => {...favorites},
    toggleFavorite: ({required String relPath, String? serial}) async {
      calls.add('toggle($relPath)');
      final error = favoriteError;
      if (error != null) throw error;
      final key = '$serial:$relPath';
      if (!favorites.remove(key)) favorites.add(key);
      return favorites.contains(key);
    },
    downloadFileBytes: (path, {String? serial, String? fileName}) async {
      calls.add('download($path)');
      if (path.contains('404')) throw const ApiException(404);
      return Uint8List.fromList([1, 2, 3]);
    },
    thumbnailUrl: (path, {String? serial, String? size}) =>
        Uri.parse('https://quark.local/thumb/$serial/$path'),
    listAlbums: ({bool tree = false}) async {
      calls.add('listAlbums');
      return albums;
    },
    createAlbum: (name, {int? parentId}) async {
      calls.add('create($name, $parentId)');
      final album = _album(9, name);
      albums = [...albums, album];
      return album;
    },
    renameAlbum: (id, name) async => throw const ApiException(409),
    deleteAlbum: (id) async => calls.add('delete($id)'),
    addPhotoToAlbum:
        (albumId, {required deviceSerial, required relPath}) async {
          if (failingAdds.contains(relPath)) throw const ApiException(500);
          calls.add('add($albumId, $relPath)');
          return PhotoAlbumItem(
            id: 1,
            albumId: albumId,
            deviceSerial: deviceSerial,
            relPath: relPath,
            addedAt: DateTime(2024),
          );
        },
    listDevices: () async => [_device('a'), _device('b', enabled: false)],
    bytesCache: PhotoBytesCache.instance,
  );
}

void main() {
  setUp(PhotoBytesCache.instance.clear);

  group('refresh', () {
    test('loads the first page, device photos, favorites and albums', () async {
      final quark = _FakeQuark(total: 60)..favorites = {'sd1:camera/1.jpg'};
      final controller = quark.controller();
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.refresh();

      expect(controller.photos, hasLength(PhotosController.pageSize));
      expect(controller.photos.first.hasLiveVideo, isTrue);
      expect(controller.photos[1].isFavorite, isTrue);
      expect(controller.hasMore, isTrue);
      expect(controller.albumsLoading, isFalse);
      expect(
        {for (final c in controller.categories) c.id: c.count},
        {'all': 61, 'quark': 60, 'mobile': 1, 'favorites': 1},
      );
      expect(notified, greaterThan(0));
    });

    test('keeps the grid until the new lists arrive', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();
      await controller.refresh();

      final pending = controller.refresh();
      expect(controller.photos, hasLength(3));
      await pending;
      expect(controller.photos, hasLength(3));
    });

    test('asks the Quark nothing when no host is chosen', () async {
      final quark = _FakeQuark()..host = null;
      final controller = quark.controller();

      await controller.refresh();

      expect(quark.calls.where((c) => c.startsWith('getPhotos')), isEmpty);
      expect(controller.quarkUnreachable, isFalse);
      expect(controller.photos, isEmpty);
    });

    test('flags an unreachable Quark rather than an empty library', () async {
      final quark = _FakeQuark()
        ..photosError = http.ClientException('connection refused');
      final controller = quark.controller();

      await controller.refresh();

      expect(controller.photos, isEmpty);
      expect(controller.quarkUnreachable, isTrue);
    });

    test('an answered failure is not "unreachable"', () async {
      final quark = _FakeQuark()..photosError = const ApiException(500);
      final controller = quark.controller();

      await controller.refresh();

      expect(controller.quarkUnreachable, isFalse);
    });
  });

  group('paging', () {
    test('appends the next page until the total is reached', () async {
      final quark = _FakeQuark(total: 70);
      final controller = quark.controller();
      await controller.refresh();

      await controller.loadMoreQuarkPhotos();

      expect(controller.photos, hasLength(70));
      expect(controller.hasMore, isFalse);
      expect(quark.calls.where((c) => c.startsWith('getPhotos')), [
        'getPhotos(0)',
        'getPhotos(50)',
      ]);

      await controller.loadMoreQuarkPhotos();
      expect(quark.calls.where((c) => c.startsWith('getPhotos')), hasLength(2));
    });

    test('waits for the first page before paging', () async {
      final quark = _FakeQuark(total: 70);
      final controller = quark.controller();

      await controller.loadMoreQuarkPhotos();

      expect(quark.calls, isEmpty);
    });

    test('drops a page that lands after a refresh', () async {
      final quark = _FakeQuark(total: 70);
      final controller = quark.controller();
      await controller.refresh();

      final more = controller.loadMoreQuarkPhotos();
      await controller.refresh();
      await more;

      expect(controller.photos, hasLength(50));
      expect(controller.isLoadingMore, isFalse);
    });
  });

  group('categories', () {
    test('filters by source and favorites, and folds the picker', () async {
      final quark = _FakeQuark()..favorites = {'sd1:camera/2.jpg'};
      final controller = quark.controller();
      await controller.refresh();
      controller.toggleCategoriesExpanded();

      controller.selectCategory(PhotoCategory.mobile);
      expect(controller.photos.map((p) => p.id), ['asset:dev1']);
      expect(controller.photos.single.isRemote, isFalse);
      expect(controller.categoriesExpanded, isFalse);

      controller.selectCategory(PhotoCategory.all);
      expect(controller.photos, hasLength(4));

      controller.selectCategory(PhotoCategory.favorites);
      expect(controller.photos.map((p) => p.id), ['sd1:camera/2.jpg']);
      expect(controller.hasMore, isFalse);
    });

    test('the web only ever shows Quark photos', () async {
      final controller = PhotosController(
        isWeb: true,
        activeHost: () => null,
        listAlbums: ({bool tree = false}) async => [],
      );

      await controller.refresh();

      expect(controller.showsCategories, isFalse);
      controller.selectCategory(PhotoCategory.mobile);
      expect(controller.photos, isEmpty);
    });
  });

  group('favorites', () {
    test('toggling updates the star and the favorites count', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();
      await controller.refresh();

      await controller.toggleFavorite('sd1:camera/1.jpg');

      expect(quark.calls, contains('toggle(camera/1.jpg)'));
      expect(controller.photos[1].isFavorite, isTrue);
      await controller.toggleFavorite('sd1:camera/1.jpg');
      expect(controller.photos[1].isFavorite, isFalse);
    });

    test('device photos cannot be favorited', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();
      await controller.refresh();

      await controller.toggleFavorite('asset:dev1');

      expect(quark.calls.where((c) => c.startsWith('toggle')), isEmpty);
    });

    test('a failure propagates and leaves the star alone', () async {
      final quark = _FakeQuark()..favoriteError = const ApiException(500);
      final controller = quark.controller();
      await controller.refresh();

      await expectLater(
        controller.toggleFavorite('sd1:camera/1.jpg'),
        throwsA(isA<ApiException>()),
      );
      expect(controller.photos[1].isFavorite, isFalse);
    });
  });

  group('selection', () {
    test('a long press starts selecting with that photo selected', () async {
      final controller = _FakeQuark().controller();
      await controller.refresh();

      controller.selectFromLongPress('sd1:camera/0.jpg');
      expect(controller.selectionMode, isTrue);
      expect(controller.selectedIds, {'sd1:camera/0.jpg'});

      controller.selectFromLongPress('sd1:camera/0.jpg');
      expect(controller.selectedIds, isEmpty);
      expect(controller.selectionMode, isTrue);
    });

    test('adding counts what was added, skipped and refused', () async {
      final quark = _FakeQuark()..failingAdds.add('camera/2.jpg');
      final controller = quark.controller();
      await controller.refresh();
      controller.enterSelectionMode(
        addingTo: const AlbumItem(id: 1, name: 'Trips'),
      );
      for (final id in ['sd1:camera/0.jpg', 'sd1:camera/2.jpg', 'asset:dev1']) {
        controller.toggleSelection(id);
      }

      final outcome = await controller.addSelectedToAlbum(1);

      expect((outcome.added, outcome.skipped, outcome.failed), (1, 1, 1));
      expect(quark.calls, contains('add(1, camera/0.jpg)'));
      expect(controller.selectionMode, isFalse);
      expect(controller.addingToAlbum, isNull);
      expect(controller.selectedIds, isEmpty);
    });
  });

  group('albums', () {
    test('lists favorites, then other system albums, then the user', () async {
      final controller = _FakeQuark().controller();

      await controller.loadAlbums();

      expect(controller.albums.map((a) => a.name), [
        'Favorites',
        'Inbox',
        'Trips',
      ]);
      expect(controller.albums.first.isFavorites, isTrue);
      expect(controller.albumById(1)?.name, 'Trips');
    });

    test('creating reloads the tree', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();

      await controller.createAlbum('Iceland', parentId: 1);

      expect(quark.calls, ['create(Iceland, 1)', 'listAlbums']);
      expect(controller.albums.map((a) => a.name), contains('Iceland'));
    });

    test('a failed rename propagates', () async {
      final controller = _FakeQuark().controller();

      await expectLater(
        controller.renameAlbum(1, 'Trip'),
        throwsA(isA<ApiException>()),
      );
    });

    test('expansion toggles', () {
      final controller = _FakeQuark().controller();

      controller.toggleAlbumExpanded(4);
      expect(controller.expandedAlbumIds, {4});
      controller.toggleAlbumExpanded(4);
      expect(controller.expandedAlbumIds, isEmpty);
    });
  });

  group('uploads', () {
    test('offers enabled devices only', () async {
      final targets = await _FakeQuark().controller().uploadTargets();

      expect(targets.map((t) => t.serial), ['a']);
    });

    test('devices that cannot be listed upload to the default', () async {
      final controller = PhotosController(
        listDevices: () async => throw const ApiException(500),
      );

      expect(await controller.uploadTargets(), isEmpty);
    });
  });

  group('viewer', () {
    test('loads through the cache and prefetches Quark photos only', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();
      await controller.refresh();

      await controller.prefetchPhotoAt(1);
      final (bytes, name, relPath, serial) = await controller.loadPhotoAt(1);

      expect(bytes, isNotNull);
      expect((name, relPath, serial), ('1.jpg', 'camera/1.jpg', 'sd1'));
      expect(quark.calls.where((c) => c.startsWith('download')), [
        'download(camera/1.jpg)',
      ]);
      expect(await controller.loadPhotoAt(99), (null, '', null, null));
    });

    test('a failed load reaches the caller unchanged', () async {
      final controller = PhotosController(
        isWeb: true,
        activeHost: () => 'h',
        listAlbums: ({bool tree = false}) async => [],
        listFavoriteKeys: () async => {},
        getPhotos: ({int offset = 0, int limit = 50, String? serial}) async =>
            wire.PaginatedPhotosResponse(
              photos: [
                const wire.PhotoItem(
                  relPath: '404.jpg',
                  fileName: '404.jpg',
                  size: 1,
                  mtime: 0,
                  serial: '',
                ),
              ],
              total: 1,
              offset: 0,
              limit: 50,
            ),
        downloadFileBytes: (path, {String? serial, String? fileName}) async =>
            throw const ApiException(404),
      );
      await controller.refresh();

      await expectLater(
        controller.loadPhotoAt(0),
        throwsA(isA<ApiException>()),
      );
    });

    test('maps thumbnails to Quark photos and assets to device ones', () async {
      final controller = _FakeQuark().controller();
      await controller.refresh();

      expect(
        controller.thumbnailUrl('sd1:camera/0.jpg'),
        Uri.parse('https://quark.local/thumb/sd1/camera/0.jpg'),
      );
      expect(controller.assetFor('sd1:camera/0.jpg'), isNull);
      expect(controller.thumbnailUrl('asset:dev1'), isNull);
      expect(controller.assetFor('asset:dev1')?.id, 'dev1');
    });
  });
}
