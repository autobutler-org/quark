import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/chart_sample.dart';

void main() {
  group('ChartData', () {
    test('fits every series to the categories', () {
      final data = ChartData(
        categories: const ['A', 'B'],
        series: [
          ChartSeries(values: const [1]),
          ChartSeries(values: const [1, 2, 3]),
        ],
      );
      expect(data.series[0].values, [1, 0]);
      expect(data.series[1].values, [1, 2]);
      expect(data.range, (min: 0.0, max: 2.0));
      expect(ChartData().range, isNull);
    });

    test('reads and writes a data sheet grid', () {
      final data = sampleChart().data;
      final grid = data.toGrid();
      expect(grid, [
        ['', 'Revenue', 'Costs'],
        ['Q1', '12', '8'],
        ['Q2', '30', '12.5'],
        ['Q3', '42', '20'],
      ]);
      expect(ChartData.fromGrid(grid), data);
    });

    test('a grid with blanks, text and short rows reads leniently', () {
      final data = ChartData.fromGrid([
        ['', 'A', 'B'],
        ['x', '1,200', 'n/a'],
        ['y', ' 50% '],
        [],
      ]);
      expect(data.categories, ['x', 'y', '']);
      expect(data.series[0].values, [1200, 50, 0]);
      expect(data.series[1].values, [0, 0, 0]);
      expect(ChartData.fromGrid(const []), ChartData());
    });

    test('a grid past the limits is refused', () {
      expect(
        () => ChartData.fromGrid([
          ['', for (var i = 0; i <= ChartData.maxSeries; i++) 's$i'],
          ['a'],
        ]),
        throwsArgumentError,
      );
    });

    test('formatChartValue drops needless decimals', () {
      expect(formatChartValue(42), '42');
      expect(formatChartValue(3.5), '3.5');
      expect(formatChartValue(-0.25), '-0.25');
      expect(formatChartValue(1 / 3), '0.33');
      expect(formatChartValue(-0.001), '0');
    });
  });

  group('ChartElement', () {
    test('colors past its own take the theme accents in turn', () {
      final chart = sampleChart();
      expect(chart.colorOf(0), const SlideColor(0xFF224488));
      expect(chart.colorOf(1), const SlideColor.theme(ThemeColor.accent2));
      expect(chart.colorOf(6), const SlideColor.theme(ThemeColor.accent1));
    });

    test('the legend names series, or a pie its slices', () {
      final chart = sampleChart();
      expect(chart.legendEntries.map((e) => e.name), ['Revenue', 'Costs']);
      final pie = chart.copyWith(kind: ChartKind.pie);
      expect(pie.legendEntries.map((e) => e.name), ['Q1', 'Q2', 'Q3']);
      expect(pie.legendEntries[1].color,
          const SlideColor.theme(ThemeColor.accent2));
    });

    test('withFrame and withId keep the chart', () {
      final chart = sampleChart();
      final moved = chart.withFrame(chart.frame.copyWith(x: 0));
      expect(moved.data, chart.data);
      expect(moved.frame.x, 0);
      expect(chart.withId('x').id, 'x');
      expect(chart.withId('x'), isNot(chart));
    });

    test('equality covers data, options and colors', () {
      final chart = sampleChart();
      expect(sampleChart(), chart);
      expect(sampleChart().hashCode, chart.hashCode);
      expect(chart.copyWith(colors: const []), isNot(chart));
      expect(
        chart.copyWith(options: chart.options.copyWith(showLegend: false)),
        isNot(chart),
      );
    });
  });

  group('screen reader text', () {
    test('a chart reads as a summary', () {
      final chart = sampleChart().copyWith(
        options: const ChartOptions(),
      );
      expect(defaultSlideElementLabel(chart),
          'Bar chart, 2 series, 3 categories; highest value 42 in Q3');
      expect(
        defaultSlideChartSummary(sampleChart().copyWith(kind: ChartKind.line)),
        'Line chart titled Sales, 2 series, 3 categories; '
        'highest value 42 in Q3',
      );
    });

    test('one series and an empty chart read naturally', () {
      final one = sampleChart().copyWith(
        kind: ChartKind.pie,
        options: const ChartOptions(),
      );
      expect(defaultSlideChartSummary(one),
          'Pie chart, 1 series, 3 categories; highest value 42 in Q3');
      expect(
        defaultSlideChartSummary(
          one.copyWith(kind: ChartKind.area, data: ChartData()),
        ),
        'Area chart, no data',
      );
    });

    test('the data reads as a labeled table', () {
      expect(
        defaultSlideChartDataLabel(sampleChart()),
        'Q1: Revenue 12, Costs 8. Q2: Revenue 30, Costs 12.5. '
        'Q3: Revenue 42, Costs 20.',
      );
      final unnamed = sampleChart().copyWith(
        data: ChartData(
          categories: const [''],
          series: [
            ChartSeries(values: const [1])
          ],
        ),
      );
      expect(defaultSlideChartDataLabel(unnamed), 'Category 1: Series 1 1.');
    });

    test('chart tools are named for what they insert', () {
      expect(defaultSlideToolLabel(const SlideCanvasTool.chart(ChartKind.pie)),
          'Insert pie chart');
      expect(
        defaultSlideToolLabel(
            const SlideCanvasTool.chart(ChartKind.horizontalBar)),
        'Insert horizontal bar chart',
      );
    });
  });
}
