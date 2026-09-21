import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
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

PhotoAlbum _album(int id, String name, {String? smartType, int count = 0}) =>
    PhotoAlbum(
      id: id,
      name: name,
      smartType: smartType,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      itemCount: count,
    );

/// A one-byte picked photo with no path on disk, so it uploads from bytes.
final class _Picked extends PlatformFile {
  _Picked(this.name);

  @override
  final String name;

  final Uint8List _bytes = Uint8List.fromList([1]);

  @override
  Uri get uri => Uri.parse('memory:$name');

  // The controller never asks for one, and cross_file is not a dependency
  // of the app to name its type.
  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

PlatformFile _picked(String name) => _Picked(name);

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
  Map<int, List<String>> albumFiles = {
    1: ['camera/1.jpg'],
  };
  Object? albumItemsError;

  /// Holds the album tree back until it completes, when set.
  Future<void>? albumsGate;
  Object? albumsError;
  final Set<String> failingAdds = {};
  final List<String> calls = [];

  /// Where the next upload says its files landed.
  List<String> landedPaths = const [];

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
      await albumsGate;
      final error = albumsError;
      if (error != null) throw error;
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
    removePhotoFromAlbum:
        (albumId, {required deviceSerial, required relPath}) async {
          calls.add('remove($albumId, $relPath)');
          albumFiles[albumId]?.remove(relPath);
        },
    listAlbumItems: (albumId) async {
      calls.add('items($albumId)');
      final error = albumItemsError;
      if (error != null) throw error;
      // Favorites mirrors the stars, the way the Quark's does (#992).
      final paths = albumId == 3
          ? [for (final key in favorites) key.substring('sd1:'.length)]
          : albumFiles[albumId] ?? const <String>[];
      return [
        for (final (i, path) in paths.indexed)
          PhotoAlbumItem(
            id: i,
            albumId: albumId,
            deviceSerial: 'sd1',
            relPath: path,
            addedAt: DateTime(2024),
          ),
      ];
    },
    listDevices: () async => [_device('a'), _device('b', enabled: false)],
    uploadFiles:
        (
          path,
          files, {
          String? serial,
          bool overwrite = false,
          bool keepBoth = false,
        }) async {
          calls.add('upload(${files.length}, $serial, keepBoth: $keepBoth)');
          return landedPaths;
        },
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

    test(
      'toggling reloads the albums so the Favorites count follows',
      () async {
        final quark = _FakeQuark();
        final controller = quark.controller();
        await controller.refresh();
        quark.calls.clear();
        quark.albums = [
          _album(3, 'Favorites', smartType: 'favorites', count: 1),
        ];

        await controller.toggleFavorite('sd1:camera/1.jpg');

        expect(quark.calls, ['toggle(camera/1.jpg)', 'listAlbums']);
        expect(controller.albums.single.itemCount, 1);
      },
    );

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

    test('the add-to-album picker leaves out system albums', () async {
      final controller = _FakeQuark().controller();

      final picked = await controller.fetchAlbums();

      expect(picked.map((a) => a.name), ['Trips']);
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

    test('a name clash leaves the tree alone and says why', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();
      await controller.loadAlbums();
      quark.calls.clear();

      Object? error;
      try {
        await controller.renameAlbum(1, 'Inbox');
      } catch (e) {
        error = e;
      }

      expect(Errors.album(error, 'rename the album'), Errors.albumNameTaken);
      expect(quark.calls, isEmpty);
      expect(controller.albums.map((a) => a.name), [
        'Favorites',
        'Inbox',
        'Trips',
      ]);
    });

    test('a name is taken by a sibling, ignoring ASCII case only', () async {
      final quark = _FakeQuark()
        ..albums = [
          ..._FakeQuark().albums,
          _album(4, 'Äb'),
          PhotoAlbum(
            id: 5,
            name: 'Places',
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
            itemCount: 0,
            children: [_album(6, 'Japan')],
          ),
        ];
      final controller = quark.controller();
      await controller.loadAlbums();

      expect(controller.albumNameTaken(' trips '), isTrue);
      // The top level is shared with the system albums.
      expect(controller.albumNameTaken('FAVORITES'), isTrue);
      expect(controller.albumNameTaken('Japan'), isFalse);
      expect(controller.albumNameTaken('japan', parentId: 5), isTrue);
      // SQLite folds ASCII case only, so the Quark allows this one.
      expect(controller.albumNameTaken('äb'), isFalse);
      // Renaming an album to another case of its own name is no clash.
      expect(controller.albumNameTaken('TRIPS', except: 1), isFalse);
    });

    test('showing an album switches the grid to its items', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();
      await controller.refresh();
      controller.selectCategory(PhotoCategory.mobile);

      await controller.showAlbum(1);

      expect(quark.calls, contains('items(1)'));
      expect(controller.selectedAlbumId, 1);
      expect(controller.selectedAlbum?.name, 'Trips');
      expect(controller.photos.map((p) => p.id), ['sd1:camera/1.jpg']);
      expect(controller.photos.single.name, '1.jpg');
      expect(controller.photoCount, 1);
      expect(controller.hasMore, isFalse);
      expect(
        controller.showsCategories,
        isFalse,
        reason: 'the categories filter the library, not an album',
      );
      expect(
        controller.thumbnailUrl('sd1:camera/1.jpg'),
        Uri.parse('https://quark.local/thumb/sd1/camera/1.jpg'),
      );
      expect((await controller.openPhotoAt(0))?.$3, 'camera/1.jpg');
    });

    test('All photos brings back the category that was showing', () async {
      final controller = _FakeQuark().controller();
      await controller.refresh();
      controller.selectCategory(PhotoCategory.mobile);
      await controller.showAlbum(1);

      await controller.showAlbum(null);

      expect(controller.selectedAlbumId, isNull);
      expect(controller.selectedCategory, PhotoCategory.mobile);
      expect(controller.showsCategories, isTrue);
      expect(controller.photos.map((p) => p.id), ['asset:dev1']);
    });

    test('a link waiting for the tree resolves once albums load', () async {
      final gate = Completer<void>();
      final quark = _FakeQuark()..albumsGate = gate.future;
      final controller = quark.controller();
      final refreshing = controller.refresh();

      await controller.showAlbumLink('7');
      await controller.showAlbumLink('trips');
      expect(controller.albumLoading, isTrue, reason: 'waits for the tree');
      expect(controller.albumLink, 'trips');
      expect(quark.calls, isNot(contains('items(1)')));

      gate.complete();
      await refreshing;

      expect(controller.selectedAlbumId, 1);
      expect(controller.albumLink, 'Trips', reason: 'the canonical spelling');
      expect(controller.photos.map((p) => p.id), ['sd1:camera/1.jpg']);
    });

    test('a failed tree load keeps the link for the next refresh', () async {
      final quark = _FakeQuark()
        ..albumsError = http.ClientException('Connection refused');
      final controller = quark.controller();
      await controller.showAlbumLink('Trips');

      await controller.refresh();

      expect(controller.albumLink, 'Trips', reason: 'the URL keeps the link');
      expect(controller.selectedAlbumId, isNull);
      expect(
        controller.albumLoading,
        isFalse,
        reason: 'no album spinner while the Quark is out of reach',
      );
      expect(quark.calls, isNot(contains('items(1)')));

      quark.albumsError = null;
      await controller.refresh();

      expect(controller.selectedAlbumId, 1);
      expect(controller.albumLink, 'Trips');
      expect(quark.calls, contains('items(1)'));
      expect(controller.photos.map((p) => p.id), ['sd1:camera/1.jpg']);
    });

    test('a link by id exposes the album name', () async {
      final controller = _FakeQuark().controller();
      await controller.refresh();

      await controller.showAlbumLink('3');

      expect(controller.selectedAlbum?.name, 'Favorites');
      expect(controller.albumLink, 'Favorites');
      expect(controller.albumLinkFor(1), 'Trips');
    });

    test('renaming the showing album changes its link', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();
      await controller.refresh();
      await controller.showAlbumLink('Trips');

      quark.albums = [_album(1, 'Voyages'), ...quark.albums.skip(1)];
      await controller.loadAlbums();

      expect(controller.selectedAlbumId, 1);
      expect(controller.albumLink, 'Voyages');
    });

    test('a link naming no album shows All photos', () async {
      final controller = _FakeQuark().controller();
      await controller.refresh();

      await controller.showAlbumLink('Nowhere');

      expect(controller.selectedAlbumId, isNull);
      expect(controller.albumLink, isNull);
      expect(controller.photoCount, 3);
    });

    test('an album missing from the tree falls back to All photos', () async {
      final controller = _FakeQuark().controller();
      await controller.refresh();

      await controller.showAlbum(42);

      expect(controller.selectedAlbumId, isNull);
      expect(controller.photoCount, 3);
    });

    test('an album that cannot be loaded says why', () async {
      final quark = _FakeQuark()..albumItemsError = const ApiException(500);
      final controller = quark.controller();
      await controller.refresh();

      await controller.showAlbum(1);

      expect(controller.albumLoading, isFalse);
      expect(controller.albumError, isA<ApiException>());
      expect(controller.quarkUnreachable, isFalse);
      expect(controller.photos, isEmpty);
    });

    test('un-starring in Favorites drops the photo from the grid', () async {
      final quark = _FakeQuark()..favorites = {'sd1:camera/0.jpg'};
      final controller = quark.controller();
      await controller.refresh();
      await controller.showAlbum(3);
      expect(controller.photos.map((p) => p.id), ['sd1:camera/0.jpg']);

      await controller.toggleFavorite('sd1:camera/0.jpg');

      expect(controller.photos, isEmpty);
    });

    test(
      'removing from the album drops the photo and reloads the tree',
      () async {
        final quark = _FakeQuark();
        final controller = quark.controller();
        await controller.refresh();
        await controller.showAlbum(1);
        quark.calls.clear();

        await controller.removeFromSelectedAlbum('sd1:camera/1.jpg');

        expect(quark.calls, ['remove(1, camera/1.jpg)', 'listAlbums']);
        expect(controller.photos, isEmpty);
      },
    );

    test('adding photos from an album returns to that album', () async {
      final quark = _FakeQuark();
      final controller = quark.controller();
      await controller.refresh();
      await controller.showAlbum(1);

      controller.enterSelectionMode(
        addingTo: const AlbumItem(id: 1, name: 'Trips'),
      );
      expect(controller.selectedAlbumId, isNull, reason: 'picks from library');
      controller.toggleSelection('sd1:camera/2.jpg');
      await controller.addSelectedToAlbum(1);
      quark.albumFiles[1]!.add('camera/2.jpg');
      await pumpEventQueue();

      expect(controller.selectionMode, isFalse);
      expect(controller.selectedAlbumId, 1);
      expect(quark.calls, contains('add(1, camera/2.jpg)'));
      expect(quark.calls.last, 'items(1)');
    });

    test('canceling the add returns to the album too', () async {
      final controller = _FakeQuark().controller();
      await controller.refresh();
      await controller.showAlbum(1);
      controller.enterSelectionMode(
        addingTo: const AlbumItem(id: 1, name: 'Trips'),
      );

      controller.exitSelectionMode();
      await pumpEventQueue();

      expect(controller.selectedAlbumId, 1);
      expect(controller.photoCount, 1);
    });

    test('adding nothing stays in adding mode to try again', () async {
      final quark = _FakeQuark()..failingAdds.add('camera/2.jpg');
      final controller = quark.controller();
      await controller.refresh();
      controller.enterSelectionMode(
        addingTo: const AlbumItem(id: 1, name: 'Trips'),
      );
      controller.toggleSelection('sd1:camera/2.jpg');

      await controller.addSelectedToAlbum(1);

      expect(controller.selectionMode, isTrue);
      expect(controller.addingToAlbum?.id, 1);
      expect(controller.selectedAlbumId, isNull);
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

    test('without an album, uploads and adds nothing', () async {
      final quark = _FakeQuark()..landedPaths = ['a.jpg'];

      final outcome = await quark.controller().uploadPhotos([_picked('a.jpg')]);

      expect(outcome, isNull);
      expect(quark.calls, ['upload(1, null, keepBoth: true)']);
    });

    test('adds each photo to the album where it landed (#2240)', () async {
      final quark = _FakeQuark()
        ..landedPaths = ['IMG_1.jpg', 'IMG_1_(1).jpg', 'b.jpg']
        ..failingAdds.add('b.jpg');

      final outcome = await quark.controller().uploadPhotos(
        [_picked('IMG_1.jpg'), _picked('IMG_1.jpg'), _picked('b.jpg')],
        serial: 'a',
        albumId: 1,
      );

      expect(quark.calls, [
        'upload(3, a, keepBoth: true)',
        'add(1, IMG_1.jpg)',
        'add(1, IMG_1_(1).jpg)',
      ]);
      expect((outcome!.added, outcome.failed), (2, 1));
      expect(outcome.error, isA<ApiException>());
    });

    test('a photo the Quark reported no path for counts as failed', () async {
      final quark = _FakeQuark();

      final outcome = await quark.controller().uploadPhotos([
        _picked('a.jpg'),
      ], albumId: 1);

      expect((outcome!.added, outcome.failed), (0, 1));
    });

    group('a drop (#2214)', () {
      DropItemFile file(String name) =>
          DropItemFile.fromData(Uint8List.fromList([1]), path: name);

      test('keeps the photos, walking into folders, and counts the rest', () {
        final (:photos, :notPhotos) = PhotosController().sortDroppedFiles([
          file('IMG_1234.jpg'),
          file('notes.txt'),
          DropItemDirectory('/trip', [
            file('RAW_1.CR2'),
            file('clip.mp4'),
            file('logo.svg'),
          ], name: 'trip'),
        ]);

        expect(photos.map((p) => p.name), ['IMG_1234.jpg', 'RAW_1.CR2']);
        expect(notPhotos, 3);
      });

      test('uploads one request a photo to the library root, keeping both '
          'on a clash', () async {
        final requests = <String>[];
        final controller = PhotosController(
          readDroppedFile: (file) async => Uint8List.fromList([1, 2, 3]),
          uploadFiles:
              (
                path,
                files, {
                serial,
                overwrite = false,
                keepBoth = false,
              }) async {
                requests.add(
                  '$path/${files.map((f) => f.filename).join(',')} '
                  'serial=$serial keepBoth=$keepBoth',
                );
                return const <String>[];
              },
        );
        final (:photos, notPhotos: _) = controller.sortDroppedFiles([
          file('a.jpg'),
          file('b.png'),
        ]);

        final uploaded = await controller.uploadDroppedPhotos(
          photos,
          serial: 'sd1',
        );

        expect(uploaded, 2);
        expect(requests, [
          '/a.jpg serial=sd1 keepBoth=true',
          '/b.png serial=sd1 keepBoth=true',
        ]);
        expect(controller.isUploading, isFalse);
      });

      test('skips a photo that reads empty and passes a failure on', () async {
        final sent = <String?>[];
        final controller = PhotosController(
          readDroppedFile: (file) async =>
              file.name == 'empty.jpg' ? Uint8List(0) : Uint8List(1),
          uploadFiles:
              (
                path,
                files, {
                serial,
                overwrite = false,
                keepBoth = false,
              }) async {
                sent.add(files.single.filename);
                if (files.single.filename == 'full.jpg') {
                  throw const ApiException(507);
                }
                return const <String>[];
              },
        );
        final (:photos, notPhotos: _) = controller.sortDroppedFiles([
          file('empty.jpg'),
          file('ok.jpg'),
          file('full.jpg'),
          file('never.jpg'),
        ]);

        await expectLater(
          controller.uploadDroppedPhotos(photos),
          throwsA(isA<ApiException>()),
        );
        expect(sent, ['ok.jpg', 'full.jpg']);
        expect(controller.isUploading, isFalse);
      });
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
