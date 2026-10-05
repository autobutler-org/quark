import 'dart:math' as math;

import '../format/json_fields.dart';
import '../format/qslide_format_exception.dart';
import 'chart_series.dart';

/// The small table of numbers a `ChartElement` draws: [categories] — the
/// labels along the category axis, or a pie's slices — by [series], each a
/// named row of one value per category.
///
/// Every series has exactly one value per category: the constructor pads a
/// short one with zeros and cuts a long one. A data sheet edits it as a grid
/// ([toGrid], [ChartData.fromGrid]) with the series names across the top and
/// the categories down the side, as spreadsheets lay chart data out.
///
/// A chart may hold at most [maxSeries] series, [maxCategories] categories
/// and [maxValues] values in all; past them a file is refused with a
/// `QslideFormatException` and an edit with an [ArgumentError], so a
/// hostile file cannot make drawing it unbounded.
///
/// ```dart
/// final data = ChartData(
///   categories: ['Q1', 'Q2', 'Q3'],
///   series: [ChartSeries(name: 'Revenue', values: [12, 30, 42])],
/// );
/// data.toGrid(); // [['', 'Revenue'], ['Q1', '12'], ['Q2', '30'], ['Q3', '42']]
/// ```
class ChartData {
  /// Creates chart data, each series fitted to [categories].
  ChartData({
    List<String> categories = const [],
    List<ChartSeries> series = const [],
  })  : categories = List.unmodifiable(categories),
        series = List.unmodifiable([
          for (final s in series) s.withLength(categories.length),
        ]);

  /// The most series a chart may have.
  static const maxSeries = 50;

  /// The most categories a chart may have.
  static const maxCategories = 500;

  /// The most values a chart may have, series times categories.
  static const maxValues = 5000;

  /// The category labels, in order.
  final List<String> categories;

  /// The series, in legend order.
  final List<ChartSeries> series;

  /// Whether the data is within [maxSeries], [maxCategories] and
  /// [maxValues].
  bool get withinLimits =>
      series.length <= maxSeries &&
      categories.length <= maxCategories &&
      series.length * categories.length <= maxValues;

  /// Every value of every series, series by series.
  Iterable<double> get values => series.expand((s) => s.values);

  /// The smallest and largest values, or `null` with none.
  ({double min, double max})? get range {
    if (values.isEmpty) return null;
    return (min: values.reduce(math.min), max: values.reduce(math.max));
  }

  /// Reads the `categories` and `series` of a chart's `.qslide` object at
  /// [path].
  factory ChartData.fromJson(JsonMap json, String path) {
    final categories = optionalList(json, 'categories', path);
    final series = optionalList(json, 'series', path);
    if (series.length > maxSeries ||
        categories.length > maxCategories ||
        series.length * categories.length > maxValues) {
      throw QslideFormatException(
        'a chart holds at most $maxSeries series, $maxCategories categories '
        'and $maxValues values',
        path: path,
      );
    }
    return ChartData(
      categories: [
        for (var i = 0; i < categories.length; i++)
          switch (categories[i]) {
            final String s => s,
            final num n => '$n',
            null => '',
            _ => throw QslideFormatException(
                'expected a string',
                path: '$path.categories[$i]',
              ),
          },
      ],
      series: [
        for (var i = 0; i < series.length; i++)
          ChartSeries.fromJson(series[i], '$path.series[$i]'),
      ],
    );
  }

  /// The `categories` and `series` fields of a chart's `.qslide` object.
  JsonMap toJson() => {
        'categories': categories,
        'series': [for (final s in series) s.toJson()],
      };

  /// Reads data from a grid of text, as a data sheet edits it: the first
  /// row holds the series names from its second cell on, the first column
  /// the categories from its second row on, and the rest the values. A
  /// value that is not a number — blank, say — reads as 0; a short row is
  /// padded. Throws an [ArgumentError] past the limits.
  factory ChartData.fromGrid(List<List<String>> grid) {
    final names = grid.isEmpty ? const <String>[] : grid.first.skip(1);
    final rows = grid.skip(1).toList();
    final data = ChartData(
      categories: [for (final row in rows) row.isEmpty ? '' : row.first],
      series: [
        for (final (i, name) in names.indexed)
          ChartSeries(
            name: name,
            values: [
              for (final row in rows)
                i + 1 < row.length ? parseValue(row[i + 1]) : 0,
            ],
          ),
      ],
    );
    if (!data.withinLimits) {
      throw ArgumentError.value(
        '${data.series.length} × ${data.categories.length}',
        'grid',
        'is past the chart limits',
      );
    }
    return data;
  }

  /// [text] read as a chart value: a number, with any thousands commas,
  /// spaces or trailing percent sign dropped; 0 when it is none.
  static double parseValue(String text) {
    final cleaned = text.replaceAll(RegExp(r'[,\s%]'), '');
    final value = double.tryParse(cleaned);
    return value != null && value.isFinite ? value : 0;
  }

  /// The data as a grid of text; see [ChartData.fromGrid].
  List<List<String>> toGrid() => [
        ['', for (final s in series) s.name],
        for (final (c, category) in categories.indexed)
          [category, for (final s in series) formatChartValue(s.values[c])],
      ];

  /// Returns a copy with the given fields replaced.
  ChartData copyWith({List<String>? categories, List<ChartSeries>? series}) =>
      ChartData(
        categories: categories ?? this.categories,
        series: series ?? this.series,
      );

  @override
  bool operator ==(Object other) =>
      other is ChartData &&
      listEquals(other.categories, categories) &&
      listEquals(other.series, series);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(categories), Object.hashAll(series));

  @override
  String toString() => 'ChartData($categories, $series)';
}

/// [value] as a chart shows it: without a fraction when it is whole, else
/// to at most two decimal places with trailing zeros dropped — `42`, `3.5`,
/// `-0.25`.
String formatChartValue(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var text = value.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text == '-0' ? '0' : text;
}
