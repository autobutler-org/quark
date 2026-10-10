/// Bounds on the listing snapshots kept on disk so a cold launch has
/// something to show before the first listing answers (#1781).
abstract final class ListingSnapshotConfig {
  /// The folder under the app's support directory that holds the snapshots.
  static const String directoryName = 'listing_cache';

  /// How many of a folder's entries `FileBrowserCache` writes. A bigger
  /// folder shows its head until the refresh lands.
  static const int maxItemsPerFolder = 500;

  /// The largest snapshot file written or read back. A file over this is
  /// deleted rather than parsed.
  static const int maxBytes = 1024 * 1024;
}
