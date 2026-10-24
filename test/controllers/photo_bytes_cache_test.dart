import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photo_bytes_cache.dart';
import 'package:quark/utils/image_viewer_config.dart';

/// #1710: navigating the viewer re-downloaded every photo, including ones
/// already seen a moment earlier. This is the cache that stops it — bounded by
/// bytes rather than item count, because a fixed count of full-size photos is
/// what OOM-kills a phone.
void main() {
  final cache = PhotoBytesCache.instance;

  /// [megabytes] of filler, so a test can spend the real budget.
  Uint8List photo(int megabytes) => Uint8List(megabytes * 1024 * 1024);

  setUp(cache.clear);
  tearDown(cache.clear);

  group('keys', () {
    test('a photo is found again by the same relPath and serial', () {
      final bytes = photo(1);
      cache.put(PhotoBytesCache.key('/photos/a.jpg', 'abc'), bytes);

      expect(cache.get(PhotoBytesCache.key('/photos/a.jpg', 'abc')), bytes);
    });

    test('the same path on another device is a different photo', () {
      cache.put(PhotoBytesCache.key('/photos/a.jpg', 'abc'), photo(1));

      expect(cache.get(PhotoBytesCache.key('/photos/a.jpg', 'xyz')), isNull);
      expect(cache.get(PhotoBytesCache.key('/photos/b.jpg', 'abc')), isNull);
    });
  });

  group('eviction', () {
    test('an evicted photo is downloaded again', () {
      const key = '/photos/a.jpg';
      cache.put(PhotoBytesCache.key(key, 'abc'), photo(4));

      cache.evict(PhotoBytesCache.key(key, 'abc'));

      expect(cache.get(PhotoBytesCache.key(key, 'abc')), isNull);
    });

    test('evicting a photo that was never held is a no-op', () {
      cache.put(PhotoBytesCache.key('/a.jpg', null), photo(4));

      cache.evict(PhotoBytesCache.key('/gone.jpg', null));

      expect(cache.get(PhotoBytesCache.key('/a.jpg', null)), isNotNull);
    });
  });

  group('byte budget', () {
    test('what fits is kept', () {
      cache.put(PhotoBytesCache.key('/a.jpg', null), photo(4));
      cache.put(PhotoBytesCache.key('/b.jpg', null), photo(4));

      expect(cache.get(PhotoBytesCache.key('/a.jpg', null)), isNotNull);
      expect(cache.get(PhotoBytesCache.key('/b.jpg', null)), isNotNull);
    });

    test('overrunning the budget evicts the least recently used photo', () {
      const megabytes = 16;
      final fits =
          ImageViewerConfig.photoCacheBudgetBytes ~/ (megabytes * 1024 * 1024);
      for (var i = 0; i < fits; i++) {
        cache.put(PhotoBytesCache.key('/$i.jpg', null), photo(megabytes));
      }
      // Touch the oldest so it is no longer the one to go.
      expect(cache.get(PhotoBytesCache.key('/0.jpg', null)), isNotNull);

      cache.put(PhotoBytesCache.key('/new.jpg', null), photo(megabytes));

      expect(cache.get(PhotoBytesCache.key('/1.jpg', null)), isNull);
      expect(cache.get(PhotoBytesCache.key('/0.jpg', null)), isNotNull);
      expect(cache.get(PhotoBytesCache.key('/new.jpg', null)), isNotNull);
    });

    test('a photo larger than the whole budget is not kept at all', () {
      cache.put(PhotoBytesCache.key('/small.jpg', null), photo(1));
      cache.put(
        PhotoBytesCache.key('/huge.jpg', null),
        Uint8List(ImageViewerConfig.photoCacheBudgetBytes + 1),
      );

      expect(cache.get(PhotoBytesCache.key('/huge.jpg', null)), isNull);
      expect(cache.get(PhotoBytesCache.key('/small.jpg', null)), isNotNull);
    });
  });

  group('fetch', () {
    test('a second look at the same photo does not download again', () async {
      var downloads = 0;
      final key = PhotoBytesCache.key('/a.jpg', null);
      Future<Uint8List?> download() async {
        downloads++;
        return photo(1);
      }

      await cache.fetch(key, download);
      await cache.fetch(key, download);

      expect(downloads, 1);
    });

    test('a prefetch and the user arriving share one download', () async {
      var downloads = 0;
      final key = PhotoBytesCache.key('/a.jpg', null);
      Future<Uint8List?> download() async {
        downloads++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return photo(1);
      }

      final prefetch = cache.fetch(key, download);
      final navigation = cache.fetch(key, download);
      final results = await Future.wait([prefetch, navigation]);

      expect(downloads, 1);
      expect(results.first, same(results.last));
    });

    // The viewer needs to tell a 404 from a dropped request (#1708), so the
    // cache must not swallow or flatten what the download threw.
    test('a failed download is not cached and its error propagates', () async {
      var downloads = 0;
      final key = PhotoBytesCache.key('/a.jpg', null);

      await expectLater(
        cache.fetch(key, () async {
          downloads++;
          throw const FormatException('dropped');
        }),
        throwsA(isA<FormatException>()),
      );
      expect(cache.get(key), isNull);

      await cache.fetch(key, () async {
        downloads++;
        return photo(1);
      });
      expect(downloads, 2);
    });
  });
}
