import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:quark/utils/thumbnail_cache_key.dart';

/// The disk cache every Quark thumbnail goes through (#1777): one store for
/// the whole app, sized by [ThumbnailCacheConfig], and the key each thumbnail
/// is filed under.
///
/// A widget passes [instance] and [keyFor] to its `CachedNetworkImage`. On the
/// web that widget leaves caching to the browser and the store goes unused.
abstract final class ThumbnailCacheManager {
  /// The one store, shared so its object budget is counted once.
  static final CacheManager instance = CacheManager(
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

  /// Forgets the thumbnail at [url], on disk in [manager] ([instance] when
  /// null) and decoded in memory, so its next load fetches it again.
  ///
  /// `CachedNetworkImage.evictFromCache` is not enough: it drops the decoded
  /// image filed under the URL, not the one under a cache key, and never the
  /// width-bounded one a photo grid tile holds.
  static Future<void> evict(Uri url, {BaseCacheManager? manager}) async {
    final key = keyFor(url);
    try {
      await (manager ?? instance).removeFile(key);
    } on Exception {
      // Best effort: bytes left behind are shown once more and then replaced,
      // since every load revalidates them by ETag.
    }
    final image = CachedNetworkImageProvider(url.toString(), cacheKey: key);
    await image.evict();
    await ResizeImage(image, width: ThumbnailCacheConfig.memCacheWidth).evict();
  }
}
