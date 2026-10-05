import 'package:flutter/material.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/slides/chart/slide_chart_data_cell.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One row of a chart's data sheet. Row 0 names the series: a "Categories"
/// caption over the first column, then a [SlideChartDataCell] per series
/// name. Every other row is a category: its name, a value per series, and
/// a button that removes it.
///
/// Cells listed in [invalid] (as columns of this row) show
/// `Errors.chartValueNotNumber`.
///
/// Key prefixes: the cells' `slide_chart_cell_<row>_<column>`, and
/// `slide_chart_remove_category_<index>` on a category's remove button.
class SlideChartDataRow extends StatelessWidget {
  /// Row [row] of a sheet whose first row is [names].
  const SlideChartDataRow({
    required this.row,
    required this.cells,
    required this.names,
    required this.invalid,
    required this.onChanged,
    this.onRemove,
    super.key,
  });

  /// Its index in the grid: 0 for the series names.
  final int row;

  /// Its text, one entry per column.
  final List<String> cells;

  /// The grid's first row, which names the columns for a screen reader.
  final List<String> names;

  /// The columns of this row whose values are not numbers.
  final Set<int> invalid;

  /// Called with a column and its new text.
  final void Function(int column, String text) onChanged;

  /// Removes the category; null for the names row, or the only category.
  final VoidCallback? onRemove;

  /// The width the trailing remove button takes.
  static const double buttonWidth = 56;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final category = row == 0 ? '' : cells.first;
    String label(int c) {
      if (row == 0) return 'Series $c name';
      final series = c < names.length ? names[c] : '';
      if (c == 0) return 'Category $row name';
      return '${category.isEmpty ? 'Category $row' : category}, '
          '${series.isEmpty ? 'Series $c' : series}';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (c, text) in cells.indexed)
          if (row == 0 && c == 0)
            SizedBox(
              width: SlideChartDataCell.width,
              child: Padding(
                padding: EdgeInsets.all(tokens.spacingSm),
                child: Text(
                  'Categories',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tokens.mutedForeground,
                  ),
                ),
              ),
            )
          else
            SlideChartDataCell(
              cellKey: 'slide_chart_cell_${row}_$c',
              label: label(c),
              initial: text,
              numeric: row > 0 && c > 0,
              header: row == 0 || c == 0,
              error: invalid.contains(c) ? Errors.chartValueNotNumber : null,
              onChanged: (value) => onChanged(c, value),
            ),
        SizedBox(
          width: buttonWidth,
          child: row == 0
              ? null
              : QuarkBarIconButton(
                  key: ValueKey('slide_chart_remove_category_${row - 1}'),
                  icon: QuarkIcons.delete_outline,
                  tooltip:
                      'Remove ${category.isEmpty ? 'category $row' : category}',
                  onPressed: onRemove,
                ),
        ),
      ],
    );
  }
}
