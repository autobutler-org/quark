/// How a `ChartElement` is dressed: its [title], whether it shows a
/// [showLegend] legend, [showDataLabels] value labels and [showGridlines]
/// gridlines, and the titles of its two axes.
///
/// An empty title is no title. A pie has no axes, so it draws neither axis
/// title nor gridlines.
///
/// In `.qslide` the options sit beside the chart's other fields, each left
/// out at its default:
///
/// ```json
/// {"title": "Sales", "legend": false, "dataLabels": true,
///  "gridlines": false, "categoryAxisTitle": "Quarter",
///  "valueAxisTitle": "USD (millions)"}
/// ```
class ChartOptions {
  /// Creates chart options.
  const ChartOptions({
    this.title = '',
    this.showLegend = true,
    this.showDataLabels = false,
    this.showGridlines = true,
    this.categoryAxisTitle = '',
    this.valueAxisTitle = '',
  });

  /// The title drawn above the chart; empty for none.
  final String title;

  /// Whether the legend is drawn, naming each series (each slice of a pie).
  final bool showLegend;

  /// Whether each bar, point or slice is labeled with its value.
  final bool showDataLabels;

  /// Whether lines are drawn across the plot at each value axis tick.
  final bool showGridlines;

  /// The title along the category axis; empty for none.
  final String categoryAxisTitle;

  /// The title along the value axis; empty for none.
  final String valueAxisTitle;

  /// Returns a copy with the given fields replaced.
  ChartOptions copyWith({
    String? title,
    bool? showLegend,
    bool? showDataLabels,
    bool? showGridlines,
    String? categoryAxisTitle,
    String? valueAxisTitle,
  }) =>
      ChartOptions(
        title: title ?? this.title,
        showLegend: showLegend ?? this.showLegend,
        showDataLabels: showDataLabels ?? this.showDataLabels,
        showGridlines: showGridlines ?? this.showGridlines,
        categoryAxisTitle: categoryAxisTitle ?? this.categoryAxisTitle,
        valueAxisTitle: valueAxisTitle ?? this.valueAxisTitle,
      );

  @override
  bool operator ==(Object other) =>
      other is ChartOptions &&
      other.title == title &&
      other.showLegend == showLegend &&
      other.showDataLabels == showDataLabels &&
      other.showGridlines == showGridlines &&
      other.categoryAxisTitle == categoryAxisTitle &&
      other.valueAxisTitle == valueAxisTitle;

  @override
  int get hashCode => Object.hash(
        title,
        showLegend,
        showDataLabels,
        showGridlines,
        categoryAxisTitle,
        valueAxisTitle,
      );
}
