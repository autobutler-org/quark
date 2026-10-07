import 'dart:math' as math;
import 'dart:ui';

/// Where the parts of a chart go inside its frame, in chart-local slide
/// units: the [title] across the top, the [legend] across the bottom, the
/// value and category axis titles and tick labels beside the plot, and the
/// [plot] in what is left.
///
/// It is plain arithmetic over sizes the painter has measured, so it is
/// tested without text: a part that is not drawn passes [Size.zero] and
/// takes no room. The value axis is on the left of a vertical chart and
/// along the bottom of a horizontal one; the category axis takes the other
/// side. [ChartLayout.of] never makes a negative rectangle: a chart too
/// small for its labels gets an empty plot.
class ChartLayout {
  /// Creates a layout from its rectangles.
  const ChartLayout({
    required this.title,
    required this.legend,
    required this.plot,
    required this.valueAxisTitle,
    required this.categoryAxisTitle,
  });

  /// The space around a chart's parts and between them, as a share of the
  /// chart's shorter side.
  static const paddingShare = 0.03;

  /// Lays out a chart [size] big.
  ///
  /// [title], [legend] and the two axis titles are the sizes of those parts
  /// as drawn — an axis title along a vertical axis is drawn turned a
  /// quarter, so its height there is its [Size.width] — and
  /// [valueLabels] and [categoryLabels] the largest tick label of each
  /// axis. [horizontal] puts categories down the side; [hasAxes] false — a
  /// pie — leaves the axes out.
  factory ChartLayout.of({
    required Size size,
    Size title = Size.zero,
    Size legend = Size.zero,
    Size valueAxisTitle = Size.zero,
    Size categoryAxisTitle = Size.zero,
    Size valueLabels = Size.zero,
    Size categoryLabels = Size.zero,
    bool horizontal = false,
    bool hasAxes = true,
  }) {
    final pad = math.min(size.width, size.height) * paddingShare;
    var top = pad;
    var bottom = size.height - pad;
    Rect band(Size part, {required bool atTop}) {
      if (part.isEmpty) return Rect.zero;
      final y = atTop ? top : bottom - part.height;
      final rect = Rect.fromLTWH(
        (size.width - part.width) / 2,
        y,
        part.width,
        part.height,
      );
      atTop ? top += part.height + pad : bottom -= part.height + pad;
      return rect;
    }

    final titleRect = band(title, atTop: true);
    final legendRect = band(legend, atTop: false);
    var left = pad;
    var right = size.width - pad;
    var valueTitle = Rect.zero;
    var categoryTitle = Rect.zero;
    if (hasAxes) {
      // The axis down the left side and the one along the bottom.
      final sideTitle = horizontal ? categoryAxisTitle : valueAxisTitle;
      final baseTitle = horizontal ? valueAxisTitle : categoryAxisTitle;
      final sideLabels = horizontal ? categoryLabels : valueLabels;
      final baseLabels = horizontal ? valueLabels : categoryLabels;
      var side = Rect.zero;
      var base = Rect.zero;
      if (!baseTitle.isEmpty) {
        base = Rect.fromLTWH(
            0, bottom - baseTitle.height, baseTitle.width, baseTitle.height);
        bottom -= baseTitle.height + pad / 2;
      }
      if (!sideTitle.isEmpty) {
        // Turned a quarter: its width runs up the side.
        side = Rect.fromLTWH(left, 0, sideTitle.height, sideTitle.width);
        left += sideTitle.height + pad / 2;
      }
      left += sideLabels.width + (sideLabels.isEmpty ? 0 : pad / 2);
      bottom -= baseLabels.height + (baseLabels.isEmpty ? 0 : pad / 2);
      final plotCenter = Offset((left + right) / 2, (top + bottom) / 2);
      if (!base.isEmpty) {
        base = base.translate(plotCenter.dx - base.width / 2, 0);
      }
      if (!side.isEmpty) {
        side = side.translate(0, plotCenter.dy - side.height / 2);
      }
      valueTitle = horizontal ? base : side;
      categoryTitle = horizontal ? side : base;
    }
    return ChartLayout(
      title: titleRect,
      legend: legendRect,
      plot: Rect.fromLTRB(
        left,
        top,
        math.max(left, right),
        math.max(top, bottom),
      ),
      valueAxisTitle: valueTitle,
      categoryAxisTitle: categoryTitle,
    );
  }

  /// The font size of a chart's title, in slide units, for a chart [size]
  /// big: 7% of its shorter side, 16 to 56.
  static double titleFontSize(Size size) =>
      (math.min(size.width, size.height) * 0.07).clamp(16.0, 56.0);

  /// The font size of a chart's labels, legend and axis titles: 4.5% of its
  /// shorter side, 12 to 32.
  static double labelFontSize(Size size) =>
      (math.min(size.width, size.height) * 0.045).clamp(12.0, 32.0);

  /// Where the title goes; [Rect.zero] for none.
  final Rect title;

  /// Where the legend goes; [Rect.zero] for none.
  final Rect legend;

  /// The plot: bars, lines, areas or the pie. Axis lines run along its
  /// left and bottom edges, tick labels outside them.
  final Rect plot;

  /// Where the value axis title goes — turned a quarter on a vertical
  /// chart — or [Rect.zero].
  final Rect valueAxisTitle;

  /// Where the category axis title goes — turned a quarter on a horizontal
  /// chart — or [Rect.zero].
  final Rect categoryAxisTitle;
}
