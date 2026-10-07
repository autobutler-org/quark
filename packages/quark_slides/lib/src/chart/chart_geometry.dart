/// The geometry of a chart's plot, as plain arithmetic over rectangles in
/// slide units: where each bar of a clustered bar chart goes, where a line
/// passes through each category, which axis labels fit without overlapping,
/// which value labels to keep, and how a legend wraps. `SlideChartPainter`
/// draws from these; they know nothing of text or color.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'chart_axis_scale.dart';

/// The share of each category's band a cluster of bars fills; the rest is
/// the gap between clusters.
const chartBarClusterShare = 0.75;

/// The middle of category [index] of [count] along an axis from [start],
/// [length] long: each category gets an equal band.
double chartCategoryCenter(int index, int count, double start, double length) =>
    start + (index + 0.5) * length / count;

/// The bar of every series in every category, `[series][category]`, for a
/// clustered bar chart over [values] (`[series][category]`) in [plot] on
/// [scale].
///
/// Each category gets an equal band — across [plot] left to right, or with
/// [horizontal] down it top to bottom — whose middle
/// [chartBarClusterShare] holds one bar per series side by side. A bar runs
/// from the scale's baseline to its value, so a negative value hangs below
/// (or left of) zero; values past the scale are clipped to it.
List<List<Rect>> chartBars({
  required List<List<double>> values,
  required Rect plot,
  required ChartAxisScale scale,
  bool horizontal = false,
}) {
  final seriesCount = values.length;
  final categories = seriesCount == 0 ? 0 : values.first.length;
  if (categories == 0) return [for (final _ in values) const []];
  final along = horizontal ? plot.height : plot.width;
  final band = along / categories;
  final bar = band * chartBarClusterShare / seriesCount;
  final first = band * (1 - chartBarClusterShare) / 2;
  double at(double value) => scale.fraction(value.clamp(scale.min, scale.max));
  final base = at(scale.baseline);
  return [
    for (var s = 0; s < seriesCount; s++)
      [
        for (var c = 0; c < categories; c++)
          () {
            final start = c * band + first + s * bar;
            final value = at(values[s][c]);
            final low = math.min(base, value);
            final high = math.max(base, value);
            return horizontal
                ? Rect.fromLTRB(
                    plot.left + low * plot.width,
                    plot.top + start,
                    plot.left + high * plot.width,
                    plot.top + start + bar,
                  )
                : Rect.fromLTRB(
                    plot.left + start,
                    plot.bottom - high * plot.height,
                    plot.left + start + bar,
                    plot.bottom - low * plot.height,
                  );
          }(),
      ],
  ];
}

/// Where a line through [values] passes over each category in [plot] on
/// [scale]: at the middle of each category's band, at the value's height,
/// held within the plot.
List<Offset> chartLinePoints(
  List<double> values,
  Rect plot,
  ChartAxisScale scale,
) =>
    [
      for (final (c, v) in values.indexed)
        Offset(
          chartCategoryCenter(c, values.length, plot.left, plot.width),
          plot.bottom -
              scale.fraction(v.clamp(scale.min, scale.max)) * plot.height,
        ),
    ];

/// The height in [plot] of [scale]'s baseline, which an area fills down
/// (or up) to.
double chartBaselineY(Rect plot, ChartAxisScale scale) =>
    plot.bottom - scale.fraction(scale.baseline) * plot.height;

/// Which of an axis's labels to draw so that none overlap: every label
/// when they fit, else every second, third and so on, starting with the
/// first.
///
/// Label `i` is centered at [centers]`[i]` along the axis and [extents]`[i]`
/// long along it; two labels overlap when less than [gap] separates them.
List<int> chartVisibleLabels(
  List<double> centers,
  List<double> extents, {
  double gap = 0,
}) {
  assert(centers.length == extents.length);
  for (var every = 1; every <= centers.length; every++) {
    final kept = [for (var i = 0; i < centers.length; i += every) i];
    var fits = true;
    for (var k = 1; k < kept.length && fits; k++) {
      final a = kept[k - 1];
      final b = kept[k];
      final space =
          (centers[b] - centers[a]).abs() - (extents[a] + extents[b]) / 2;
      fits = space >= gap;
    }
    if (fits) return kept;
  }
  return centers.isEmpty ? const [] : const [0];
}

/// Which of [labels] — value labels' boxes, in drawing order — to draw:
/// each one is kept unless it overlaps one kept before it or reaches
/// outside [bounds].
List<bool> chartPlaceLabels(List<Rect> labels, Rect bounds) {
  final kept = <Rect>[];
  return [
    for (final label in labels)
      () {
        final fits = label.left >= bounds.left - 1e-6 &&
            label.top >= bounds.top - 1e-6 &&
            label.right <= bounds.right + 1e-6 &&
            label.bottom <= bounds.bottom + 1e-6 &&
            !kept.any((k) => k.overlaps(label));
        if (fits) kept.add(label);
        return fits;
      }(),
  ];
}

/// Lays [items] out in rows no wider than [maxWidth], [gap] apart, each
/// row centered and [rowGap] below the last: where each item's top-left
/// corner goes, relative to the whole, and the size of the whole. An item
/// wider than [maxWidth] gets a row of its own.
({List<Offset> offsets, Size size}) chartFlow(
  List<Size> items,
  double maxWidth, {
  double gap = 0,
  double rowGap = 0,
}) {
  final rows = <List<int>>[];
  var width = 0.0;
  for (final (i, item) in items.indexed) {
    if (rows.isEmpty || width + gap + item.width > maxWidth) {
      rows.add([i]);
      width = item.width;
    } else {
      rows.last.add(i);
      width += gap + item.width;
    }
  }
  double rowWidth(List<int> row) =>
      row.fold(0.0, (w, i) => w + items[i].width) + gap * (row.length - 1);
  final total = rows.isEmpty ? 0.0 : rows.map(rowWidth).reduce(math.max);
  final offsets = List.filled(items.length, Offset.zero);
  var y = 0.0;
  for (final row in rows) {
    var x = (total - rowWidth(row)) / 2;
    final height = row.map((i) => items[i].height).reduce(math.max);
    for (final i in row) {
      offsets[i] = Offset(x, y + (height - items[i].height) / 2);
      x += items[i].width + gap;
    }
    y += height + rowGap;
  }
  return (
    offsets: offsets,
    size: Size(total, rows.isEmpty ? 0 : y - rowGap),
  );
}
