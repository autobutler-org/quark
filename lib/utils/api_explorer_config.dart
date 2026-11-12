/// Tuning for the API explorer's "try it" requests (#4077): how much of a
/// response it reads before it stops, so a file download or the event stream
/// never loads an unbounded body into memory or holds the page forever.
abstract final class ApiExplorerConfig {
  /// The most of a response body the explorer reads and shows. The rest is
  /// never read, and the response is marked truncated.
  static const int maxResponseBytes = 64 * 1024;

  /// The longest the explorer reads a response body. A stream that stays open
  /// under [maxResponseBytes], like `/api/v0/events`, is cut off here and
  /// marked truncated.
  static const Duration maxResponseReadTime = Duration(seconds: 10);
}
