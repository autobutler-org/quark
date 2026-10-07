import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/chart/slide_chart_data_cell.dart';
import 'package:quark/widgets/slides/chart/slide_chart_data_row.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The row above a chart's data sheet: a button over each series column
/// that removes that series, off while only one is left.
///
/// Key prefixes: `slide_chart_remove_series_<index>`.
class SlideChartSeriesRemoveRow extends StatelessWidget {
  /// Remove buttons for the series named [names].
  const SlideChartSeriesRemoveRow({
    required this.names,
    required this.onRemove,
    super.key,
  });

  /// The series' names, in order.
  final List<String> names;

  /// Removes series [index]; null while only one is left.
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final remove = onRemove;
    return Row(
      children: [
        const SizedBox(width: SlideChartDataCell.width),
        for (final (i, name) in names.indexed)
          SizedBox(
            width: SlideChartDataCell.width,
            child: Center(
              child: QuarkBarIconButton(
                key: ValueKey('slide_chart_remove_series_$i'),
                icon: QuarkIcons.delete_outline,
                tooltip: 'Remove ${name.isEmpty ? 'series ${i + 1}' : name}',
                onPressed: remove == null ? null : () => remove(i),
              ),
            ),
          ),
        const SizedBox(width: SlideChartDataRow.buttonWidth),
      ],
    );
  }
}
