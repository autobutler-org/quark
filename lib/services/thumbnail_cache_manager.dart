import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/cache_manager_image.dart';
import 'package:quark/utils/decode_once_image.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:quark/utils/thumbnail_cache_key.dart';

/// The disk cache every Quark thumbnail goes through (#1777): one store for
/// the whole app, sized by [ThumbnailCacheConfig], and the key each thumbnail
/// is filed under.
///
/// A widget shows [image]. On the web caching is left to the browser and the
/// store goes unused.
abstract final class ThumbnailCacheManager {
  /// The one store, shared so its object budget is counted once. A test
  /// swaps in a fake one so thumbnails load without the network or a disk.
  static BaseCacheManager instance = CacheManager(
    Config(
      ThumbnailCacheConfig.storeKey,
      stalePeriod: ThumbnailCacheConfig.stalePeriod,
      maxNrOfCacheObjects: ThumbnailCacheConfig.maxObjects,
    ),
  );

  /// The cache key for the thumbnail at [url], as built by
  /// `FilesService.constructThumbnailUrl`: the active Quark, the account
  /// signed in on it, and the file, but never the session token in [url].
  static String keyFor(Uri url) => thumbnailCacheKey(
    url,
    host: AppSettings.instance.activeHost,
    account: AppSettings.instance.username,
  );

  /// The thumbnail at [url] as a photo grid tile shows it: from [instance],
  /// decoded at [ThumbnailCacheConfig.memCacheWidth], and decoded once
  /// however often its tile is scrolled away and back (#3366).
  static ImageProvider image(Uri url) => DecodeOnceImage(
    ResizeImage(
      CacheManagerImage(
        url.toString(),
        cacheKey: keyFor(url),
        cacheManager: instance,
      ),
      width: ThumbnailCacheConfig.memCacheWidth,
    ),
  );

  /// Forgets the thumbnail at [url], on disk in [manager] ([instance] when
  /// null) and decoded in memory, so its next load fetches it again.
  ///
  /// Every decoded copy goes: the full-size one, the width-bounded one a
  /// photo grid tile holds, and the [image] around it.
  static Future<void> evict(Uri url, {BaseCacheManager? manager}) async {
    final key = keyFor(url);
    try {
      await (manager ?? instance).removeFile(key);
    } on Exception {
      // Best effort: bytes left behind are shown once more and then replaced,
      // since every load revalidates them by ETag.
    }
    final image = CacheManagerImage(
      url.toString(),
      cacheKey: key,
      cacheManager: manager ?? instance,
    );
    await image.evict();
    final resized = ResizeImage(
      image,
      width: ThumbnailCacheConfig.memCacheWidth,
    );
    await resized.evict();
    await DecodeOnceImage(resized).evict();
  }
}
