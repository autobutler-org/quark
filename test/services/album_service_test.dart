import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

const _albumJson = {
  'id': 1,
  'name': 'Trips',
  'createdAt': '2024-01-01T00:00:00Z',
  'updatedAt': '2024-01-01T00:00:00Z',
};

const _itemJson = {
  'id': 1,
  'albumId': 1,
  'deviceSerial': 'sd1',
  'relPath': 'camera/1.jpg',
  'addedAt': '2024-01-01T00:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cache = AlbumsCache.instance;

  /// Answers every request with [status] and [body].
  void answer(int status, [Object? body]) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient(
      (request) async =>
          http.Response(body == null ? '' : jsonEncode(body), status),
    );
  }

  List<PhotoAlbumItem>? items(int albumId) => cache.items(
    albumId,
    sort: PhotoSortField.added,
    order: PhotoSortOrder.desc,
  );

  // The tree and the items of albums 1 and 2, as two visits left them.
  setUp(() {
    cache.putAlbums([PhotoAlbum.fromJson(_albumJson)]);
    for (final albumId in [1, 2]) {
      cache.putItems(
        albumId,
        [PhotoAlbumItem.fromJson(_itemJson)],
        sort: PhotoSortField.added,
        order: PhotoSortOrder.desc,
      );
    }
  });
  tearDown(() {
    cache.clear();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  group('the albums kept for the session (#1779)', () {
    test('creating an album forgets the tree', () async {
      answer(201, _albumJson);

      await AlbumService.createAlbum('Trips');

      expect(cache.albums, isNull);
      expect(items(1), isNotNull);
    });

    test('renaming an album forgets the tree', () async {
      answer(200, _albumJson);

      await AlbumService.renameAlbum(1, 'Trips');

      expect(cache.albums, isNull);
      expect(items(1), isNotNull);
    });

    test('moving an album forgets the tree', () async {
      answer(200, _albumJson);

      await AlbumService.moveAlbum(1, parentId: 2);

      expect(cache.albums, isNull);
      expect(items(1), isNotNull);
    });

    test('deleting an album forgets the tree and its items', () async {
      answer(204);

      await AlbumService.deleteAlbum(1);

      expect(cache.albums, isNull);
      expect(items(1), isNull);
      expect(items(2), isNotNull);
    });

    test('adding a photo forgets that album\'s items', () async {
      answer(201, _itemJson);

      await AlbumService.addPhotoToAlbum(
        1,
        deviceSerial: 'sd1',
        relPath: 'camera/1.jpg',
      );

      expect(items(1), isNull);
      expect(items(2), isNotNull);
      expect(cache.albums, isNotNull);
    });

    test('removing a photo forgets that album\'s items', () async {
      answer(204);

      await AlbumService.removePhotoFromAlbum(
        1,
        deviceSerial: 'sd1',
        relPath: 'camera/1.jpg',
      );

      expect(items(1), isNull);
      expect(items(2), isNotNull);
      expect(cache.albums, isNotNull);
    });

    test('a change the Quark refused forgets nothing', () async {
      answer(500, {'error': 'boom'});

      await expectLater(
        AlbumService.deleteAlbum(1),
        throwsA(isA<ApiException>()),
      );

      expect(cache.albums, isNotNull);
      expect(items(1), isNotNull);
    });
  });
}
