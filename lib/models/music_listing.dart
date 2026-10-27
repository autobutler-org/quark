/// One page of a music listing and how many items the whole listing holds,
/// as `/api/v0/music/{tracks,albums,artists}` return them.
class MusicListing<T> {
  /// Creates a page.
  const MusicListing({required this.items, required this.total});

  /// A listing with nothing in it, before the first fetch.
  const MusicListing.empty() : items = const [], total = 0;

  /// The items fetched so far, in the order asked for.
  final List<T> items;

  /// How many items the listing holds across every page.
  final int total;

  /// Whether the listing holds items not fetched yet.
  bool get hasMore => items.length < total;

  /// This page with [next] appended, taking [next]'s total, which is newer.
  MusicListing<T> followedBy(MusicListing<T> next) =>
      MusicListing(items: [...items, ...next.items], total: next.total);
}
