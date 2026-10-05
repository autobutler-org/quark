import 'package:flutter/material.dart';
import 'package:quark/utils/slide_chart_grid.dart';
import 'package:quark/widgets/slides/chart/slide_chart_data_cell.dart';
import 'package:quark/widgets/slides/chart/slide_chart_data_row.dart';
import 'package:quark/widgets/slides/chart/slide_chart_series_remove_row.dart';

/// A chart's numbers as an editable grid (#1160): series across the top,
/// categories down the side, a remove button over each series and beside
/// each category. It scrolls both ways and builds its rows lazily, so a
/// chart at the limit of 500 categories stays cheap.
///
/// [grid] is read once per cell: a cell keeps its own text and reports
/// changes through [onChanged]. A caller that changes the grid's shape
/// gives the sheet a new key, so its cells start again from [grid].
///
/// Key prefixes: `slide_chart_data_sheet` on the sheet; its rows' own.
class SlideChartDataSheet extends StatelessWidget {
  /// An editable sheet of [grid].
  const SlideChartDataSheet({
    required this.grid,
    required this.onChanged,
    required this.onRemoveSeries,
    required this.onRemoveCategory,
    super.key,
  });

  /// The data as text, in `SlideChartGrid`'s shape.
  final List<List<String>> grid;

  /// Called with a cell's row, column and new text.
  final void Function(int row, int column, String text) onChanged;

  /// Removes series [index].
  final ValueChanged<int> onRemoveSeries;

  /// Removes category [index].
  final ValueChanged<int> onRemoveCategory;

  @override
  Widget build(BuildContext context) {
    final invalid = SlideChartGrid.invalidCells(grid);
    final names = grid.first;
    final width =
        names.length * SlideChartDataCell.width + SlideChartDataRow.buttonWidth;
    return Scrollbar(
      child: SingleChildScrollView(
        key: const ValueKey('slide_chart_data_sheet'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: ListView.builder(
            itemCount: grid.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return SlideChartSeriesRemoveRow(
                  names: names.skip(1).toList(),
                  onRemove: SlideChartGrid.canRemoveSeries(grid)
                      ? onRemoveSeries
                      : null,
                );
              }
              final row = i - 1;
              return SlideChartDataRow(
                row: row,
                cells: grid[row],
                names: names,
                invalid: {
                  for (final (r, c) in invalid)
                    if (r == row) c,
                },
                onChanged: (c, text) => onChanged(row, c, text),
                onRemove: row > 0 && SlideChartGrid.canRemoveCategory(grid)
                    ? () => onRemoveCategory(row - 1)
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}
