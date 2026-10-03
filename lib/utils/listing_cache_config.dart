/// Bounds on what the Docs and Sheets pages keep in memory between visits
/// (#1780).
abstract final class ListingCacheConfig {
  /// How many by-type listings `FileTypeListingCache` keeps, across Quarks,
  /// accounts and file types. Docs and Sheets use two types per account.
  static const int maxListings = 8;

  /// How many recent content searches `ContentSearchService` remembers.
  static const int maxSearches = 32;
}
