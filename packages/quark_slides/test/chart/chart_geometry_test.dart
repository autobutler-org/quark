import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  group('ChartAxisScale.nice', () {
    test('rounds out to steps of 1, 2, 2.5 or 5 times a power of ten', () {
      final scale = ChartAxisScale.nice(0, 42);
      expect(scale.min, 0);
      expect(scale.max, 50);
      expect(scale.step, 10);
      expect(scale.ticks, [0, 10, 20, 30, 40, 50]);
    });

    test('keeps within the tick budget', () {
      for (final (low, high) in [
        (0.0, 1.0),
        (0.0, 7.0),
        (-3.0, 17.0),
        (0.0, 999.0),
        (0.0, 0.03),
        (-120.0, -5.0),
        (12345.0, 98765.0),
      ]) {
        final scale = ChartAxisScale.nice(low, high);
        expect(scale.ticks.length, lessThanOrEqualTo(6), reason: '$low..$high');
        expect(scale.min, lessThanOrEqualTo(low));
        expect(scale.max, greaterThanOrEqualTo(high));
        final mantissa = scale.step /
            math.pow(10, (math.log(scale.step) / math.ln10).floor());
        expect(
          [1, 2, 2.5, 5, 10].any((m) => (mantissa - m).abs() < 1e-9),
          isTrue,
          reason: '${scale.step}',
        );
      }
    });

    test('ticks land on round decimals, free of float error', () {
      final scale = ChartAxisScale.nice(0, 0.7);
      expect(scale.ticks, [0, 0.2, 0.4, 0.6, 0.8]);
      expect(scale.label(0.6), '0.6');
    });

    test('spans negative values across zero', () {
      final scale = ChartAxisScale.nice(-15, 25);
      expect(scale.min, -20);
      expect(scale.max, 30);
      expect(scale.baseline, 0);
      expect(scale.fraction(5), 0.5);
    });

    test('widens a single value to reach zero', () {
      expect(ChartAxisScale.nice(0, 0).max, 1);
      expect(ChartAxisScale.nice(5, 5).min, 0);
      expect(ChartAxisScale.nice(-5, -5).max, 0);
    });

    test('an all-negative axis has its baseline at the top', () {
      final scale = ChartAxisScale.nice(-40, -10);
      expect(scale.max, lessThanOrEqualTo(0));
      expect(scale.baseline, scale.max);
    });
  });

  group('ChartPieSlice.of', () {
    test('shares the circle in proportion, clockwise from the top', () {
      final slices = ChartPieSlice.of([1, 1, 2]);
      expect(slices.map((s) => s.index), [0, 1, 2]);
      expect(slices.first.startAngle, -math.pi / 2);
      expect(slices[0].sweepAngle, closeTo(math.pi / 2, 1e-12));
      expect(slices[1].startAngle, closeTo(0, 1e-12));
      expect(slices[2].sweepAngle, closeTo(math.pi, 1e-12));
      expect(slices[2].share, closeTo(0.5, 1e-12));
      expect(slices[1].midAngle, closeTo(math.pi / 4, 1e-12));
      final total = slices.fold(0.0, (a, s) => a + s.sweepAngle);
      expect(total, closeTo(2 * math.pi, 1e-12));
    });

    test('drops zero and negative values', () {
      final slices = ChartPieSlice.of([3, 0, -2, 1]);
      expect(slices.map((s) => s.index), [0, 3]);
      expect(slices.first.share, closeTo(0.75, 1e-12));
    });

    test('has no slices without a positive value', () {
      expect(ChartPieSlice.of([0, -1]), isEmpty);
      expect(ChartPieSlice.of([]), isEmpty);
    });
  });

  group('chartBars', () {
    const plot = Rect.fromLTWH(0, 0, 400, 100);
    final scale = ChartAxisScale.nice(0, 100);

    test('clusters each category in the middle of its band', () {
      final bars = chartBars(
        values: [
          [50, 100],
          [25, 0],
        ],
        plot: plot,
        scale: scale,
      );
      // Two bands of 200; clusters 150 wide, 25 in; bars 75 wide.
      expect(bars[0][0], const Rect.fromLTRB(25, 50, 100, 100));
      expect(bars[1][0], const Rect.fromLTRB(100, 75, 175, 100));
      expect(bars[0][1], const Rect.fromLTRB(225, 0, 300, 100));
      expect(bars[1][1].height, 0);
    });

    test('hangs a negative bar below the baseline', () {
      final bars = chartBars(
        values: [
          [-10, 10],
        ],
        plot: plot,
        scale: ChartAxisScale.nice(-10, 10),
      );
      expect(bars[0][0].top, 50);
      expect(bars[0][0].bottom, 100);
      expect(bars[0][1].bottom, 50);
    });

    test('lays horizontal bars down the plot, the first on top', () {
      final bars = chartBars(
        values: [
          [50, 100],
        ],
        plot: const Rect.fromLTWH(10, 0, 100, 400),
        scale: scale,
        horizontal: true,
      );
      expect(bars[0][0], const Rect.fromLTRB(10, 25, 60, 175));
      expect(bars[0][1], const Rect.fromLTRB(10, 225, 110, 375));
    });

    test('clips values past the scale', () {
      final bars = chartBars(
        values: [
          [500],
        ],
        plot: plot,
        scale: scale,
      );
      expect(bars[0][0].top, 0);
    });

    test('draws nothing without categories', () {
      expect(chartBars(values: [[]], plot: plot, scale: scale), [[]]);
    });
  });

  test('chartLinePoints pass over each band center at the value', () {
    final points = chartLinePoints(
      [0, 50, 100, 25],
      const Rect.fromLTWH(0, 0, 400, 100),
      ChartAxisScale.nice(0, 100),
    );
    expect(points, const [
      Offset(50, 100),
      Offset(150, 50),
      Offset(250, 0),
      Offset(350, 75),
    ]);
    expect(
      chartBaselineY(
          const Rect.fromLTWH(0, 0, 400, 100), ChartAxisScale.nice(-10, 10)),
      50,
    );
  });

  group('label collision', () {
    test('every label shows when they fit', () {
      expect(chartVisibleLabels([10, 30, 50], [10, 10, 10]), [0, 1, 2]);
    });

    test('crowded labels are thinned to every second, third, …', () {
      final centers = [for (var i = 0; i < 10; i++) i * 10.0];
      expect(chartVisibleLabels(centers, List.filled(10, 15)), [0, 2, 4, 6, 8]);
      expect(chartVisibleLabels(centers, List.filled(10, 25)), [0, 3, 6, 9]);
      expect(chartVisibleLabels(centers, List.filled(10, 10), gap: 1),
          [0, 2, 4, 6, 8]);
    });

    test('value labels that overlap a kept one or leave the bounds drop', () {
      const bounds = Rect.fromLTWH(0, 0, 100, 100);
      expect(
        chartPlaceLabels(const [
          Rect.fromLTWH(10, 10, 20, 10),
          Rect.fromLTWH(20, 15, 20, 10), // overlaps the first
          Rect.fromLTWH(50, 10, 20, 10),
          Rect.fromLTWH(90, 10, 20, 10), // past the right edge
        ], bounds),
        [true, false, true, false],
      );
    });
  });

  test('chartFlow wraps a legend into centered rows', () {
    final flow = chartFlow(
      const [Size(40, 10), Size(40, 10), Size(40, 20)],
      100,
      gap: 10,
      rowGap: 5,
    );
    expect(flow.size, const Size(90, 35));
    expect(flow.offsets, const [Offset(0, 0), Offset(50, 0), Offset(25, 15)]);
  });

  group('ChartLayout.of', () {
    const size = Size(1000, 600);
    final pad = 600 * ChartLayout.paddingShare;

    test('the title goes on top and the legend at the bottom, centered', () {
      final layout = ChartLayout.of(
        size: size,
        title: const Size(200, 50),
        legend: const Size(300, 30),
        hasAxes: false,
      );
      expect(layout.title, Rect.fromLTWH(400, pad, 200, 50));
      expect(layout.legend, Rect.fromLTWH(350, 600 - pad - 30, 300, 30));
      expect(layout.plot.top, pad + 50 + pad);
      expect(layout.plot.bottom, 600 - pad - 30 - pad);
      expect(layout.valueAxisTitle, Rect.zero);
    });

    test('tick labels and axis titles take room beside the plot', () {
      final layout = ChartLayout.of(
        size: size,
        valueLabels: const Size(40, 20),
        categoryLabels: const Size(60, 20),
        valueAxisTitle: const Size(100, 20),
        categoryAxisTitle: const Size(80, 20),
      );
      expect(layout.plot.left, pad + 20 + pad / 2 + 40 + pad / 2);
      expect(layout.plot.bottom, 600 - pad - 20 - pad / 2 - 20 - pad / 2);
      // The value axis title is turned up the left side, centered on the
      // plot; the category axis title is centered under it.
      expect(layout.valueAxisTitle.size, const Size(20, 100));
      expect(layout.valueAxisTitle.center.dy,
          closeTo(layout.plot.center.dy, 1e-9));
      expect(layout.categoryAxisTitle.center.dx,
          closeTo(layout.plot.center.dx, 1e-9));
    });

    test('a horizontal chart swaps which axis goes where', () {
      final layout = ChartLayout.of(
        size: size,
        valueAxisTitle: const Size(100, 20),
        categoryAxisTitle: const Size(80, 20),
        horizontal: true,
      );
      expect(layout.categoryAxisTitle.size, const Size(20, 80));
      expect(layout.valueAxisTitle.size, const Size(100, 20));
      expect(layout.valueAxisTitle.top, greaterThan(layout.plot.bottom));
    });

    test('a chart too small for its parts gets an empty plot', () {
      final layout = ChartLayout.of(
        size: const Size(50, 40),
        title: const Size(40, 30),
        legend: const Size(40, 30),
        valueLabels: const Size(60, 10),
      );
      expect(layout.plot.width, greaterThanOrEqualTo(0));
      expect(layout.plot.height, greaterThanOrEqualTo(0));
      expect(layout.plot.isEmpty, isTrue);
    });

    test('font sizes follow the chart, within bounds', () {
      expect(
          ChartLayout.titleFontSize(const Size(1200, 700)), closeTo(49, 1e-9));
      expect(ChartLayout.titleFontSize(const Size(100, 100)), 16);
      expect(ChartLayout.labelFontSize(const Size(4000, 4000)), 32);
    });
  });
}
