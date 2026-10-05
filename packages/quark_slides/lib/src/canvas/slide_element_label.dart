import '../model/chart_data.dart';
import '../model/chart_kind.dart';
import '../model/slide_element.dart';
import 'slide_tool_label.dart';

/// Names a slide element for a screen reader.
///
/// `SlideCanvas` takes one of these so an app can localize the labels; the
/// default is [defaultSlideElementLabel].
typedef SlideElementLabel = String Function(SlideElement element);

/// English screen reader labels: a text box reads its text, a line per
/// non-blank paragraph (its placeholder, or "Empty text box", when it has
/// none), an image its alt
/// text, a shape its kind, a table its size ("Table, 3 rows by 4 columns";
/// its cells read on their own, see [defaultSlideTableCellLabel]), a chart
/// its summary (see [defaultSlideChartSummary]; its numbers read as the
/// value, see [defaultSlideChartDataLabel]), a group
/// how many elements it holds. A layout
/// placeholder announces its role first: "Title: Quarterly review", or
/// "Title placeholder: Click to add title" while it is empty.
///
/// ```dart
/// defaultSlideElementLabel(ImageElement(..., altText: 'A dog'));
/// // 'Image: A dog'
/// ```
String defaultSlideElementLabel(SlideElement element) => switch (element) {
      TextBox(slot: _?, :final textRole, :final plainText, :final placeholder)
          when plainText.trim().isEmpty =>
        [
          '${textRole.label} placeholder',
          if (placeholder.isNotEmpty) placeholder,
        ].join(': '),
      final TextBox box when box.slot != null => '${box.textRole.label}: '
          '${defaultSlideElementLabel(box.copyWith(slot: null))}',
      TextBox(:final plainText, :final placeholder)
          when plainText.trim().isEmpty =>
        placeholder.isEmpty ? 'Empty text box' : placeholder,
      TextBox(:final plainText) => [
          for (final line in plainText.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ].join('\n'),
      ShapeElement(:final kind) => '${_capitalized(shapeKindName(kind))} shape',
      ImageElement(:final altText) when altText.isEmpty => 'Image',
      ImageElement(:final altText) => 'Image: $altText',
      LineElement(:final startCap, :final endCap)
          when startCap == LineCap.arrow || endCap == LineCap.arrow =>
        'Arrow',
      LineElement() => 'Line',
      TableElement(:final rowCount, :final columnCount) =>
        'Table, ${_count(rowCount, 'row')} by ${_count(columnCount, 'column')}',
      final ChartElement chart => defaultSlideChartSummary(chart),
      GroupElement(:final children) => 'Group of ${children.length}',
      UnknownElement(:final type) => 'Unsupported $type element',
    };

String _count(int n, String noun, [String? plural]) =>
    n == 1 ? '1 $noun' : '$n ${plural ?? '${noun}s'}';

String _capitalized(String s) => s[0].toUpperCase() + s.substring(1);

/// Names one cell of a table for a screen reader, from its [row] and
/// [column] counted from 0 and its [text].
///
/// `SlideCanvas` takes one of these so an app can localize the labels; the
/// default is [defaultSlideTableCellLabel].
typedef SlideTableCellLabel = String Function(int row, int column, String text);

/// English cell labels, counted from 1: "Row 2, column 3: Revenue", or
/// "Row 2, column 3: empty" for a blank cell.
String defaultSlideTableCellLabel(int row, int column, String text) {
  final shown = text.trim().replaceAll('\n', ' ');
  return 'Row ${row + 1}, column ${column + 1}: '
      '${shown.isEmpty ? 'empty' : shown}';
}

/// Reads a chart's numbers to a screen reader, as the value of the element
/// whose label is its summary.
///
/// `SlideCanvas` takes one of these so an app can localize the labels; the
/// default is [defaultSlideChartDataLabel].
typedef SlideChartDataLabel = String Function(ChartElement chart);

/// The English name of a [kind] of chart: "Bar chart", "Horizontal bar
/// chart", "Line chart", "Pie chart", "Area chart".
String chartKindName(ChartKind kind) => switch (kind) {
      ChartKind.bar => 'Bar chart',
      ChartKind.horizontalBar => 'Horizontal bar chart',
      ChartKind.line => 'Line chart',
      ChartKind.pie => 'Pie chart',
      ChartKind.area => 'Area chart',
    };

/// An English summary of [chart]: its kind, its title, how much data it
/// draws and where its highest value is — "Bar chart, 3 series, 5
/// categories; highest value 42 in Q3", or "Line chart titled Sales, 1
/// series, 4 categories; highest value 9.5 in Q2". A pie counts its first
/// series only, which is all it draws.
String defaultSlideChartSummary(ChartElement chart) {
  final kind = chartKindName(chart.kind);
  final title = chart.options.title.trim();
  final named = title.isEmpty ? kind : '$kind titled $title';
  final data = chart.data;
  final series =
      chart.kind == ChartKind.pie ? data.series.take(1).toList() : data.series;
  if (series.isEmpty || data.categories.isEmpty) return '$named, no data';
  var best = (series: 0, category: 0);
  for (final (s, values) in series.map((s) => s.values).indexed) {
    for (final (c, v) in values.indexed) {
      if (v > series[best.series].values[best.category]) {
        best = (series: s, category: c);
      }
    }
  }
  final value = series[best.series].values[best.category];
  final category = data.categories[best.category].trim();
  return '$named, ${_count(series.length, 'series', 'series')}, '
      '${_count(data.categories.length, 'category', 'categories')}; '
      'highest value ${formatChartValue(value)}'
      '${category.isEmpty ? '' : ' in $category'}';
}

/// An English reading of [chart]'s data as a labeled table, a sentence per
/// category: "Q1: Revenue 12, Costs 8. Q2: Revenue 30, Costs 9." A series
/// without a name is "Series 2"; a category without one "Category 3".
String defaultSlideChartDataLabel(ChartElement chart) {
  final data = chart.data;
  final series =
      chart.kind == ChartKind.pie ? data.series.take(1).toList() : data.series;
  return [
    for (final (c, category) in data.categories.indexed)
      '${category.trim().isEmpty ? 'Category ${c + 1}' : category.trim()}: '
          '${[
        for (final (s, one) in series.indexed)
          '${one.name.trim().isEmpty ? 'Series ${s + 1}' : one.name.trim()} '
              '${formatChartValue(one.values[c])}',
      ].join(', ')}.',
  ].join(' ');
}
