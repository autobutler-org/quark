import 'dart:math' as math;

import '../model/chart_data.dart';

/// A value axis's range and ticks, chosen so that the ticks fall on round
/// numbers: steps of 1, 2, 2.5 or 5 times a power of ten.
///
/// ```dart
/// final scale = ChartAxisScale.nice(0, 42);
/// scale.ticks; // [0, 10, 20, 30, 40, 50]
/// scale.fraction(25); // 0.5, halfway up the axis
/// ```
class ChartAxisScale {
  /// Creates a scale from [min] to [max] with ticks every [step].
  const ChartAxisScale({
    required this.min,
    required this.max,
    required this.step,
  })  : assert(max > min),
        assert(step > 0);

  /// The scale that covers [low] to [high] in at most [maxTicks] ticks on
  /// round numbers, its ends on ticks. A range of one value is widened to
  /// reach zero — or to 0 to 1 when the value is zero — so a single bar
  /// still has height.
  factory ChartAxisScale.nice(double low, double high, {int maxTicks = 6}) {
    assert(maxTicks >= 2);
    if (low > high) (low, high) = (high, low);
    if (low == high) {
      if (low == 0) {
        high = 1;
      } else if (low > 0) {
        low = 0;
      } else {
        high = 0;
      }
    }
    final rough = (high - low) / (maxTicks - 1);
    final magnitude =
        math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final step = _niceSteps.map((s) => s * magnitude).firstWhere(
        (s) => _ticksFor(low, high, s) <= maxTicks,
        orElse: () => 10 * magnitude);
    return ChartAxisScale(
      min: _snap((low / step).floor() * step, step),
      max: _snap((high / step).ceil() * step, step),
      step: step,
    );
  }

  static const _niceSteps = [1.0, 2.0, 2.5, 5.0, 10.0];

  /// How many ticks a scale over [low] to [high] has at [step].
  static int _ticksFor(double low, double high, double step) =>
      ((high / step).ceil() - (low / step).floor()) + 1;

  /// [value] rounded to the decimals [step] has, so 0.1 + 0.2 reads 0.3.
  static double _snap(double value, double step) {
    final decimals = _decimalsOf(step);
    return double.parse(value.toStringAsFixed(decimals));
  }

  static int _decimalsOf(double step) {
    var decimals = 0;
    while (decimals < 10 &&
        (step * math.pow(10, decimals)).roundToDouble() !=
            step * math.pow(10, decimals)) {
      decimals++;
    }
    return decimals;
  }

  /// The value at the bottom (or left) end of the axis.
  final double min;

  /// The value at the top (or right) end of the axis.
  final double max;

  /// The distance between ticks.
  final double step;

  /// Every tick, from [min] to [max].
  List<double> get ticks => [
        for (var i = 0; i <= ((max - min) / step).round(); i++)
          _snap(min + i * step, step),
      ];

  /// Where [value] falls along the axis: 0 at [min], 1 at [max].
  double fraction(double value) => (value - min) / (max - min);

  /// The value bars and areas grow from: zero, held within the axis.
  double get baseline => 0.0.clamp(min, max);

  /// [value] as a tick label: see [formatChartValue].
  String label(double value) => formatChartValue(value);

  @override
  bool operator ==(Object other) =>
      other is ChartAxisScale &&
      other.min == min &&
      other.max == max &&
      other.step == step;

  @override
  int get hashCode => Object.hash(min, max, step);

  @override
  String toString() => 'ChartAxisScale($min to $max by $step)';
}
