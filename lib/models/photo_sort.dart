/// How the photo grid orders its items: All photos, every category tab, and
/// every album view (#2509).
enum PhotoSortField {
  /// Date added — the file's modified time on the Quark. The default.
  added('added'),

  /// Filename, case-insensitive.
  name('name');

  const PhotoSortField(this.apiValue);

  /// The `sort` query parameter value the backend expects.
  final String apiValue;
}

/// The direction a [PhotoSortField] orders in.
enum PhotoSortOrder {
  /// Smallest/earliest first.
  asc('asc'),

  /// Largest/latest first. The default.
  desc('desc');

  const PhotoSortOrder(this.apiValue);

  /// The `order` query parameter value the backend expects.
  final String apiValue;
}
