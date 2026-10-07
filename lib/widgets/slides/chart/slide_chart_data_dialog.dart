import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/slide_chart_grid.dart';
import 'package:quark/widgets/slides/chart/slide_chart_data_sheet.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// "Edit data" for the selected slide chart (#1160): its numbers in a
/// [SlideChartDataSheet], series across the top and categories down the
/// side, with "Add series", "Add category" and "Paste", which reads a table
/// copied from a spreadsheet (tab-separated text) over the sheet.
///
/// Nothing changes until OK, which hands the whole grid to [onApply] — one
/// `setChartData` undo step. A value that is not a number is flagged in
/// its cell and keeps OK off; a grid past the chart limits, or a paste with
/// no table in it, says so above the sheet in `Errors`' words, and so does
/// an [onApply] that throws. Cancel, Escape or the close button leave the
/// chart as it was.
///
/// Key prefixes: `slide_chart_data_dialog` on the dialog,
/// `slide_chart_add_series`, `slide_chart_add_category`,
/// `slide_chart_paste`, `slide_chart_data_error`, `slide_chart_data_cancel`
/// and `slide_chart_data_ok`; the sheet's cells and remove buttons.
///
/// ```dart
/// SlideChartDataDialog.edit(context, controller);
/// ```
class SlideChartDataDialog extends StatefulWidget {
  /// A dialog editing [grid].
  const SlideChartDataDialog({
    required this.grid,
    required this.onApply,
    this.readClipboard,
    super.key,
  });

  /// The chart's data as text, in `SlideChartGrid`'s shape.
  final List<List<String>> grid;

  /// Applies the edited grid; may throw, which the dialog reports.
  final ValueChanged<List<List<String>>> onApply;

  /// Reads the clipboard's text; null where the clipboard cannot be read,
  /// which turns "Paste" off.
  final Future<String?> Function()? readClipboard;

  /// How tall the sheet of cells is; it scrolls within.
  static const double sheetHeight = 280;

  /// Opens the dialog on [controller]'s selected chart, when it may be
  /// edited, and applies OK through `setChartDataGrid`.
  static Future<void> edit(
    BuildContext context,
    SlideEditorController controller,
  ) async {
    final chart = controller.selectedChart;
    if (chart == null || !controller.canEditChart) return;
    await showDialog<void>(
      context: context,
      builder: (_) => SlideChartDataDialog(
        grid: chart.data.toGrid(),
        onApply: controller.setChartDataGrid,
        readClipboard: isClipboardAvailable ? readClipboardText : null,
      ),
    );
  }

  @override
  State<SlideChartDataDialog> createState() => _SlideChartDataDialogState();
}

class _SlideChartDataDialogState extends State<SlideChartDataDialog> {
  late List<List<String>> _grid = [
    for (final row in widget.grid) [...row],
  ];

  /// Bumped when the grid changes shape, so the sheet's cells start again.
  int _generation = 0;
  String? _error;

  void _reshape(List<List<String>> grid, {String? error}) => setState(() {
    _grid = grid;
    _generation++;
    _error = error;
  });

  Future<void> _paste() async {
    final pasted = SlideChartGrid.parseTsv(await widget.readClipboard?.call());
    if (!mounted) return;
    if (pasted == null) {
      setState(() => _error = Errors.chartPasteNoTable);
    } else if (!SlideChartGrid.withinLimits(pasted)) {
      setState(() => _error = Errors.chartTooLarge);
    } else {
      _reshape(pasted);
    }
  }

  void _ok() {
    try {
      widget.onApply(_grid);
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = Errors.chartData(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final text = Theme.of(context).textTheme;
    final valid = SlideChartGrid.invalidCells(_grid).isEmpty;
    final error = _error;
    return Dialog(
      key: const ValueKey('slide_chart_data_dialog'),
      insetPadding: EdgeInsets.all(tokens.spacingMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        // Everything scrolls together, so a phone at a large text size still
        // reaches OK; the sheet scrolls inside a fixed height.
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: tokens.spacingSm,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('Edit chart data', style: text.titleLarge),
                    ),
                  ),
                  QuarkBarIconButton(
                    key: const ValueKey('slide_chart_data_close'),
                    icon: QuarkIcons.close,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                'Series go across the top and categories down the side. '
                'A blank value counts as 0.',
                style: text.bodySmall?.copyWith(color: tokens.mutedForeground),
              ),
              Wrap(
                spacing: tokens.spacingSm,
                runSpacing: tokens.spacingSm,
                children: [
                  QuarkBarChip(
                    key: const ValueKey('slide_chart_add_series'),
                    icon: QuarkIcons.insert_column_right,
                    label: 'Add series',
                    tooltip: 'Add a series after the last',
                    keepLabel: true,
                    onPressed: SlideChartGrid.canAddSeries(_grid)
                        ? () => _reshape(SlideChartGrid.addSeries(_grid))
                        : null,
                  ),
                  QuarkBarChip(
                    key: const ValueKey('slide_chart_add_category'),
                    icon: QuarkIcons.insert_row_below,
                    label: 'Add category',
                    tooltip: 'Add a category after the last',
                    keepLabel: true,
                    onPressed: SlideChartGrid.canAddCategory(_grid)
                        ? () => _reshape(SlideChartGrid.addCategory(_grid))
                        : null,
                  ),
                  QuarkBarChip(
                    key: const ValueKey('slide_chart_paste'),
                    icon: QuarkIcons.paste_data,
                    label: 'Paste',
                    tooltip:
                        'Replace the data with cells copied from a '
                        'spreadsheet',
                    keepLabel: true,
                    onPressed: widget.readClipboard == null ? null : _paste,
                  ),
                ],
              ),
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const ValueKey('slide_chart_data_error'),
                    style: text.bodyMedium?.copyWith(color: tokens.error),
                  ),
                ),
              SizedBox(
                height: SlideChartDataDialog.sheetHeight,
                child: SlideChartDataSheet(
                  key: ValueKey('slide_chart_sheet_$_generation'),
                  grid: _grid,
                  onChanged: (r, c, value) => setState(() {
                    _grid[r][c] = value;
                    _error = null;
                  }),
                  onRemoveSeries: (i) =>
                      _reshape(SlideChartGrid.removeSeries(_grid, i)),
                  onRemoveCategory: (i) =>
                      _reshape(SlideChartGrid.removeCategory(_grid, i)),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: tokens.spacingSm,
                runSpacing: tokens.spacingSm,
                children: [
                  TextButton(
                    key: const ValueKey('slide_chart_data_cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const ValueKey('slide_chart_data_ok'),
                    onPressed: valid ? _ok : null,
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
