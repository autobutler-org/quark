/// How many columns the photo grid shows, and the tuning values behind that.
///
/// The reader picks a column count with the sidebar's slider, but a phone
/// cannot honor eight columns without shrinking every tile to a smear, so the
/// choice is clamped by how much room the grid actually has. Both the slider
/// bounds and the grid's own column count come from here, so the two cannot
/// disagree.
class PhotoGridConfig {
  const PhotoGridConfig._();

  /// The column count a fresh install starts at.
  static const int defaultColumns = 4;

  /// The fewest columns the slider ever offers.
  static const int minColumns = 1;

  /// The most columns the slider ever offers.
  static const int maxColumns = 8;

  /// The narrowest a tile is allowed to become before the column count has to
  /// come down.
  static const double minTileWidth = 80;

  /// The most Quark photos `PhotosListCache` keeps between visits to the
  /// Photos page (#1778): one page. A refresh shows the first page again, so
  /// anything past it would be on screen only until that refresh landed.
  static const int maxCachedPhotos = 50;

  /// The column bounds at [availableWidth]: the scale limits, further clamped
  /// so a tile never has to shrink below [minTileWidth].
  static ({int min, int max}) columnBounds(double availableWidth) {
    final maxByWidth = (availableWidth / minTileWidth).floor().clamp(1, 100);
    var min = minColumns;
    var max = maxColumns;
    if (min > maxByWidth) min = maxByWidth;
    if (max > maxByWidth) max = maxByWidth;
    if (min > max) min = max;
    return (min: min, max: max);
  }

  /// The column count to lay the grid out with: [preferredColumns] as chosen
  /// by the reader, clamped to what fits in [availableWidth].
  static int columnsFor(double availableWidth, int preferredColumns) {
    final bounds = columnBounds(availableWidth);
    return preferredColumns.clamp(bounds.min, bounds.max);
  }
}
