/// Tuning for the disk cache Quark thumbnails are kept in (#1777), read by
/// `ThumbnailCacheManager` and the widgets that draw a thumbnail.
abstract final class ThumbnailCacheConfig {
  /// Names the cache's folder and its index file. Its own name, so the
  /// thumbnails do not share a budget with whatever else the default cache
  /// manager holds. Changing it orphans every thumbnail already on disk.
  static const String storeKey = 'quarkThumbnails';

  /// How many thumbnails are kept before the least recently used are dropped.
  /// The default cache manager keeps 200, which one scroll through a photo
  /// library churns through; this covers a library of a few thousand photos.
  static const int maxObjects = 5000;

  /// How long a thumbnail nobody has looked at stays on disk. This is not how
  /// long it is trusted: the Quark answers with `Cache-Control: no-cache`, so
  /// every load shows the cached bytes at once and revalidates them by ETag.
  static const Duration stalePeriod = Duration(days: 30);

  /// The widest a photo grid tile's thumbnail is decoded, in pixels. The Quark
  /// already serves nothing wider — this is its largest tier — but the decoder
  /// cannot know that, so the bound keeps an oversized response from costing
  /// its full size in memory once per tile.
  static const int memCacheWidth = 400;
}
