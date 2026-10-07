/// Which edges of a range of table cells a border change draws, as a
/// toolbar's border menu names them. See `CellFormat.borders`.
enum CellBorderPreset {
  /// Every edge, outside and in.
  all,

  /// The four edges around the range.
  outside,

  /// Every edge between cells inside the range.
  inside,

  /// The edges between the range's rows.
  insideHorizontal,

  /// The edges between the range's columns.
  insideVertical,

  /// The edge along the range's top.
  top,

  /// The edge along the range's bottom.
  bottom,

  /// The edge along the range's left.
  left,

  /// The edge along the range's right.
  right,

  /// No edges: every line in and around the range is removed.
  none,
}
