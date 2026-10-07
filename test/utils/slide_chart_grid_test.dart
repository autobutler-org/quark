import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/slide_chart_grid.dart';
import 'package:quark_slides/quark_slides.dart';

/// The grid a chart's data is edited as (#1160): which cells hold numbers,
/// adding and removing series and categories within the chart limits, and
/// reading a table pasted from a spreadsheet.
void main() {
  const grid = [
    ['', 'Revenue', 'Costs'],
    ['Q1', '12', '8'],
    ['Q2', '30', '9'],
  ];

  test('a value is a number, blank, or a number with commas or a percent', () {
    for (final ok in ['12', '-3.5', '', '  ', '1,200', '45%', '1e3']) {
      expect(SlideChartGrid.isValue(ok), isTrue, reason: ok);
    }
    for (final bad in ['abc', '12x', 'NaN', 'Infinity', '--1']) {
      expect(SlideChartGrid.isValue(bad), isFalse, reason: bad);
    }
  });

  test('invalidCells names the values that are not numbers, never the '
      'names', () {
    const edited = [
      ['', 'abc', 'Costs'],
      ['Q?', 'twelve', '8'],
      ['Q2', '30', 'x'],
    ];
    expect(SlideChartGrid.invalidCells(edited), {(1, 1), (2, 2)});
    expect(SlideChartGrid.invalidCells(grid), isEmpty);
  });

  test('counts series and categories', () {
    expect(SlideChartGrid.seriesCount(grid), 2);
    expect(SlideChartGrid.categoryCount(grid), 2);
  });

  test('adds a named series of zeros and a named category of zeros', () {
    final more = SlideChartGrid.addSeries(grid);
    expect(more.first, ['', 'Revenue', 'Costs', 'Series 3']);
    expect(more.skip(1).map((r) => r.last), ['0', '0']);
    final longer = SlideChartGrid.addCategory(grid);
    expect(longer.last, ['Category 3', '0', '0']);
    expect(grid, hasLength(3), reason: 'the input is left alone');
  });

  test('removes a series or a category, never the last one', () {
    expect(SlideChartGrid.removeSeries(grid, 0), [
      ['', 'Costs'],
      ['Q1', '8'],
      ['Q2', '9'],
    ]);
    expect(SlideChartGrid.removeCategory(grid, 1), [
      ['', 'Revenue', 'Costs'],
      ['Q1', '12', '8'],
    ]);
    final one = SlideChartGrid.removeSeries(grid, 1);
    expect(SlideChartGrid.canRemoveSeries(one), isFalse);
    expect(SlideChartGrid.removeSeries(one, 0), one);
    final single = SlideChartGrid.removeCategory(grid, 0);
    expect(SlideChartGrid.canRemoveCategory(single), isFalse);
  });

  test('stops adding at the chart limits', () {
    final wide = [
      ['', for (var i = 0; i < ChartData.maxSeries; i++) 'S$i'],
      ['Q1', for (var i = 0; i < ChartData.maxSeries; i++) '1'],
    ];
    expect(SlideChartGrid.withinLimits(wide), isTrue);
    expect(SlideChartGrid.canAddSeries(wide), isFalse);
    expect(SlideChartGrid.canAddCategory(wide), isTrue);
    final full = [
      ['', for (var i = 0; i < 10; i++) 'S$i'],
      for (var r = 0; r < ChartData.maxValues ~/ 10; r++)
        ['C$r', for (var i = 0; i < 10; i++) '1'],
    ];
    expect(SlideChartGrid.withinLimits(full), isTrue);
    expect(SlideChartGrid.canAddCategory(full), isFalse);
    expect(SlideChartGrid.canAddSeries(full), isFalse);
    expect(
      SlideChartGrid.withinLimits(SlideChartGrid.addCategory(full)),
      isFalse,
    );
  });

  test('reads tab-separated text as a padded grid', () {
    expect(SlideChartGrid.parseTsv('\tA\tB\r\nQ1\t1\t2\nQ2\t3\n'), [
      ['', 'A', 'B'],
      ['Q1', '1', '2'],
      ['Q2', '3', ''],
    ]);
  });

  test('pasted text with no table in it reads as none', () {
    expect(SlideChartGrid.parseTsv(null), isNull);
    expect(SlideChartGrid.parseTsv(''), isNull);
    expect(SlideChartGrid.parseTsv('just words'), isNull);
    expect(SlideChartGrid.parseTsv('a\tb'), isNull, reason: 'no categories');
    expect(SlideChartGrid.parseTsv('a\nb'), isNull, reason: 'no series');
  });
}
