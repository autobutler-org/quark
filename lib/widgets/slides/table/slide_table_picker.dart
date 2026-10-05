import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/table/slide_table_size_grid.dart';
import 'package:quark/widgets/slides/table/slide_table_size_stepper.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Insert > Table (#1160): picks a table's rows and columns on an 8 by 8
/// [SlideTableSizeGrid] — hovered and tapped — or with the
/// [SlideTableSizeStepper]s, up to [maxSize] each, starting at [rows] by
/// [columns] (3 by 3).
///
/// Tapping the grid, or "Draw", calls [onDraw] to arm the table tool, so a
/// click on the slide places the table and a drag sizes it; "Insert" calls
/// [onInsert] to put it in the middle of the slide, which is the way in
/// from the keyboard. Either closes the menu the picker is in.
///
/// Key prefixes: `slide_table_picker` on the picker,
/// `slide_table_size_readout` on the size it reads, `slide_table_draw` and
/// `slide_table_insert` on the buttons; the grid's and steppers' own
/// (`slide_table_rows_*`, `slide_table_columns_*`).
class SlideTablePicker extends StatefulWidget {
  /// A picker starting at [rows] by [columns].
  const SlideTablePicker({
    required this.onDraw,
    required this.onInsert,
    this.rows = 3,
    this.columns = 3,
    super.key,
  });

  /// Arms the table tool with the size picked.
  final void Function(int rows, int columns) onDraw;

  /// Puts a table of the size picked in the middle of the slide.
  final void Function(int rows, int columns) onInsert;

  /// The rows it starts at.
  final int rows;

  /// The columns it starts at.
  final int columns;

  /// The most rows or columns the steppers reach.
  static const maxSize = 20;

  /// How many squares the grid has across and down.
  static const gridExtent = 8;

  @override
  State<SlideTablePicker> createState() => _SlideTablePickerState();
}

class _SlideTablePickerState extends State<SlideTablePicker> {
  late int _rows = widget.rows;
  late int _columns = widget.columns;

  void _resize(int rows, int columns) => setState(() {
    _rows = rows;
    _columns = columns;
  });

  void _done(void Function(int rows, int columns) action, int r, int c) {
    MenuController.maybeOf(context)?.close();
    action(r, c);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final size = '$_rows by $_columns';
    return Padding(
      key: const ValueKey('slide_table_picker'),
      padding: EdgeInsets.all(tokens.spacingMd),
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: tokens.spacingSm,
          children: [
            Center(
              child: SlideTableSizeGrid(
                rows: _rows.clamp(1, SlideTablePicker.gridExtent),
                columns: _columns.clamp(1, SlideTablePicker.gridExtent),
                extent: SlideTablePicker.gridExtent,
                onHover: _resize,
                onPicked: (r, c) => _done(widget.onDraw, r, c),
              ),
            ),
            Text(
              '$_rows × $_columns table',
              key: const ValueKey('slide_table_size_readout'),
              semanticsLabel: '$size table',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: tokens.foreground),
            ),
            SlideTableSizeStepper(
              name: 'rows',
              label: 'Rows',
              value: _rows,
              max: SlideTablePicker.maxSize,
              onChanged: (r) => _resize(r, _columns),
            ),
            SlideTableSizeStepper(
              name: 'columns',
              label: 'Columns',
              value: _columns,
              max: SlideTablePicker.maxSize,
              onChanged: (c) => _resize(_rows, c),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: tokens.spacingSm,
              runSpacing: tokens.spacingSm,
              children: [
                QuarkBarChip(
                  key: const ValueKey('slide_table_draw'),
                  icon: QuarkIcons.select_tool,
                  label: 'Draw',
                  tooltip: 'Draw a $size table on the slide',
                  keepLabel: true,
                  onPressed: () => _done(widget.onDraw, _rows, _columns),
                ),
                QuarkBarChip(
                  key: const ValueKey('slide_table_insert'),
                  icon: QuarkIcons.insert_table,
                  label: 'Insert',
                  tooltip: 'Insert a $size table in the middle of the slide',
                  keepLabel: true,
                  onPressed: () => _done(widget.onInsert, _rows, _columns),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
