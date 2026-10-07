/// The kinds of chart a `ChartElement` draws. A kind this version does not
/// know makes the whole element an `UnknownElement`, kept verbatim.
enum ChartKind {
  /// Vertical bars, one cluster per category, one bar per series.
  bar,

  /// Horizontal bars, categories down the side, the first at the top.
  horizontalBar,

  /// A line per series through each category's value.
  line,

  /// The first series' values as slices of a circle, one per category.
  pie,

  /// A line per series filled down to the value axis's zero.
  area;

  /// Whether the kind has a category and a value axis; a pie has neither.
  bool get hasAxes => this != pie;
}
