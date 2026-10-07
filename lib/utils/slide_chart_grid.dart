import 'package:quark_slides/quark_slides.dart';

/// A slide chart's data as the "Edit data" dialog edits it (#1160): a grid
/// of text with the series names across the first row from its second cell
/// on, the categories down the first column from its second row on, and
/// the values in between — the shape `ChartData.toGrid` and
/// `ChartData.fromGrid` use.
///
/// Every function returns a new grid and leaves its input alone. A series
/// or category added gets a numbered name and zeros; the last series and
/// the last category are never removed; nothing is added past the
/// `ChartData` limits.
///
/// ```dart
/// final grid = SlideChartGrid.addSeries(chart.data.toGrid());
/// SlideChartGrid.invalidCells(grid); // {} while every value is a number
/// ```
abstract final class SlideChartGrid {
  /// Whether [text] reads as a chart value: blank (read as 0), or a finite
  /// number, with any thousands commas, spaces or a percent sign, as
  /// `ChartData.parseValue` reads it.
  static bool isValue(String text) {
    final cleaned = text.replaceAll(RegExp(r'[,\s%]'), '');
    if (cleaned.isEmpty) return true;
    final value = double.tryParse(cleaned);
    return value != null && value.isFinite;
  }

  /// The value cells of [grid], as (row, column), that are not numbers.
  /// The names in the first row and column are never checked.
  static Set<(int, int)> invalidCells(List<List<String>> grid) => {
    for (var r = 1; r < grid.length; r++)
      for (var c = 1; c < grid[r].length; c++)
        if (!isValue(grid[r][c])) (r, c),
  };

  /// How many series [grid] holds.
  static int seriesCount(List<List<String>> grid) =>
      grid.isEmpty ? 0 : grid.first.length - 1;

  /// How many categories [grid] holds.
  static int categoryCount(List<List<String>> grid) =>
      grid.isEmpty ? 0 : grid.length - 1;

  static bool _fits(int series, int categories) =>
      series <= ChartData.maxSeries &&
      categories <= ChartData.maxCategories &&
      series * categories <= ChartData.maxValues;

  /// Whether [grid] is within the `ChartData` limits.
  static bool withinLimits(List<List<String>> grid) =>
      _fits(seriesCount(grid), categoryCount(grid));

  /// Whether [addSeries] stays within the limits.
  static bool canAddSeries(List<List<String>> grid) =>
      _fits(seriesCount(grid) + 1, categoryCount(grid));

  /// Whether [addCategory] stays within the limits.
  static bool canAddCategory(List<List<String>> grid) =>
      _fits(seriesCount(grid), categoryCount(grid) + 1);

  /// Whether [grid] has a series to spare.
  static bool canRemoveSeries(List<List<String>> grid) => seriesCount(grid) > 1;

  /// Whether [grid] has a category to spare.
  static bool canRemoveCategory(List<List<String>> grid) =>
      categoryCount(grid) > 1;

  /// [grid] with a series "Series N" of zeros after the last.
  static List<List<String>> addSeries(List<List<String>> grid) => [
    for (final (r, row) in grid.indexed)
      [...row, r == 0 ? 'Series ${seriesCount(grid) + 1}' : '0'],
  ];

  /// [grid] with a category "Category N" of zeros after the last.
  static List<List<String>> addCategory(List<List<String>> grid) => [
    ...grid.map((row) => [...row]),
    [
      'Category ${categoryCount(grid) + 1}',
      for (var i = 0; i < seriesCount(grid); i++) '0',
    ],
  ];

  /// [grid] without series [index]; unchanged when it is the only one.
  static List<List<String>> removeSeries(List<List<String>> grid, int index) =>
      [
        for (final row in grid)
          [
            for (final (c, cell) in row.indexed)
              if (c != index + 1 || !canRemoveSeries(grid)) cell,
          ],
      ];

  /// [grid] without category [index]; unchanged when it is the only one.
  static List<List<String>> removeCategory(
    List<List<String>> grid,
    int index,
  ) => [
    for (final (r, row) in grid.indexed)
      if (r != index + 1 || !canRemoveCategory(grid)) [...row],
  ];

  /// Tab-separated [text] — cells copied from a spreadsheet — as a grid,
  /// short rows padded with blanks; null unless it holds at least a series
  /// and a category (two rows of two cells).
  static List<List<String>>? parseTsv(String? text) {
    if (text == null) return null;
    final lines = text.split(RegExp(r'\r?\n'));
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    final rows = [for (final line in lines) line.split('\t')];
    final width = rows.fold(0, (w, row) => row.length > w ? row.length : w);
    if (rows.length < 2 || width < 2) return null;
    return [
      for (final row in rows)
        [...row, for (var i = row.length; i < width; i++) ''],
    ];
  }
}
