import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';

/// Records what [ThumbnailCacheManager.evict] drops from disk.
class _RecordingCacheManager extends Fake implements BaseCacheManager {
  final removed = <String>[];

  @override
  Future<void> removeFile(String key) async => removed.add(key);
}

/// An image that never arrives, enough to occupy a slot in the image cache.
class _PendingImage extends ImageStreamCompleter {}

/// The test binding answers every request with HTTP 400. Let the load fail,
/// unmount, then fail if an image error escaped.
Future<void> _finish(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  /// #2603: the photo tile around a thumbnail is the button a screen reader
  /// names; the picture inside it adds nothing to say, so it stays out of the
  /// semantics tree rather than turning the tile into an unlabeled image.
  for (final (label, thumbnail) in [
    ('a Quark photo', PhotoThumbnail(url: Uri.parse('http://quark/t.jpg'))),
    (
      'a Quark photo that can backfill',
      PhotoThumbnail(
        url: Uri.parse('http://quark/t.jpg'),
        path: '/photos/t.heic',
      ),
    ),
    (
      'a sample photo',
      PhotoThumbnail(
        url: Uri(scheme: 'asset', path: 'assets/demo/aurora.jpg'),
      ),
    ),
  ]) {
    testWidgets('$label is not announced as an image', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Semantics(
              container: true,
              button: true,
              label: 'beach.jpg',
              child: SizedBox.square(dimension: 100, child: thumbnail),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('beach.jpg'))
            .flagsCollection
            .isImage,
        isFalse,
      );
      handle.dispose();
      await _finish(tester);
    });
  }

  /// #1777: a Quark photo's thumbnail used to live only in the in-memory image
  /// cache, so every cold launch downloaded the whole grid again.
  for (final (label, path) in [
    ('a Quark photo', null),
    ('a Quark photo that can backfill', '/photos/t.heic'),
  ]) {
    final url = Uri.parse(
      'http://quark/api/v0/thumbnails/photos/t.heic?token=secret-token',
    );

    testWidgets('$label is cached on disk under a token-free key', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoThumbnail(url: url, path: path),
        ),
      );

      final cached = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(cached.imageUrl, url.toString());
      expect(cached.cacheKey, ThumbnailCacheManager.keyFor(url));
      expect(cached.cacheKey, isNot(contains('secret-token')));
      expect(cached.cacheManager, same(ThumbnailCacheManager.instance));
      expect(cached.memCacheWidth, ThumbnailCacheConfig.memCacheWidth);
      await _finish(tester);
    });

    testWidgets('evicting $label drops the image its tile decoded', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoThumbnail(url: url, path: path),
        ),
      );
      final decoded = await tester
          .widget<Image>(find.byType(Image))
          .image
          .obtainKey(ImageConfiguration.empty);
      await _finish(tester);
      imageCache.putIfAbsent(decoded, _PendingImage.new);

      final manager = _RecordingCacheManager();
      await ThumbnailCacheManager.evict(url, manager: manager);

      expect(manager.removed, [ThumbnailCacheManager.keyFor(url)]);
      expect(imageCache.containsKey(decoded), isFalse);
    });
  }
}
