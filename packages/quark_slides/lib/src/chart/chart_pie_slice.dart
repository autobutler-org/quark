import 'dart:math' as math;

/// One slice of a pie: the category at [index], its [value], and the angle
/// it covers, in radians clockwise from the top.
///
/// [ChartPieSlice.of] lays a pie out from its values.
class ChartPieSlice {
  /// Creates a slice.
  const ChartPieSlice({
    required this.index,
    required this.value,
    required this.startAngle,
    required this.sweepAngle,
  });

  /// The angle the first slice starts at: straight up, as Flutter measures
  /// angles (clockwise from the positive x axis).
  static const top = -math.pi / 2;

  /// The slices of a pie of [values], in order, clockwise from the top:
  /// each a share of the circle in proportion to its value. A value that is
  /// zero or negative has no slice; with no positive value there are none.
  static List<ChartPieSlice> of(List<double> values) {
    final total = values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    if (total <= 0) return const [];
    final slices = <ChartPieSlice>[];
    var angle = top;
    for (final (i, v) in values.indexed) {
      if (v <= 0) continue;
      final sweep = v / total * 2 * math.pi;
      slices.add(ChartPieSlice(
        index: i,
        value: v,
        startAngle: angle,
        sweepAngle: sweep,
      ));
      angle += sweep;
    }
    return slices;
  }

  /// The category the slice draws.
  final int index;

  /// The slice's value.
  final double value;

  /// Where the slice starts, in radians.
  final double startAngle;

  /// How far round the slice reaches, in radians.
  final double sweepAngle;

  /// The angle through the slice's middle, where its label goes.
  double get midAngle => startAngle + sweepAngle / 2;

  /// The share of the whole pie the slice is, 0 to 1.
  double get share => sweepAngle / (2 * math.pi);

  @override
  bool operator ==(Object other) =>
      other is ChartPieSlice &&
      other.index == index &&
      other.value == value &&
      other.startAngle == startAngle &&
      other.sweepAngle == sweepAngle;

  @override
  int get hashCode => Object.hash(index, value, startAngle, sweepAngle);
}
