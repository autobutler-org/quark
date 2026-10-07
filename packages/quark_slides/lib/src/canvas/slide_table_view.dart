import 'package:flutter/widgets.dart';

import '../model/cell_range.dart';
import '../model/slide_element.dart';
import '../theme/slide_theme.dart';
import 'slide_canvas_style.dart';
import 'slide_element_label.dart';
import 'slide_table_border_painter.dart';
import 'slide_table_cell_view.dart';

/// The inside of a [TableElement], in table-local slide units: each cell's
/// fill and text, then the borders over them.
///
/// A merged cell is drawn once, across its whole area; the cells it covers
/// are not drawn. A cell's text is laid out by [SlideTextBoxView] from
/// `TableElement.cellTextBox`, inside the cell's padding — the same
/// paragraph layout a text box uses, so it wraps the same way in the
/// in-place editor. Header row text that leaves its color unset is drawn in
/// the theme's background color, over the header's accent (see
/// [cellTheme]).
///
/// Each cell is keyed `slide_table_cell_<id>_<row>_<column>` (see
/// [cellKeyName]) and reads to a screen reader as [cellLabel] names it
/// ("Row 2, column 3: Revenue"), marked selected when it is in
/// [selectedCells]. The cell [editingCell], when one is being edited, is
/// drawn as [editor]. [selectedCells] are tinted with
/// `SlideCanvasStyle.selectionColor`.
class SlideTableView extends StatelessWidget {
  /// Creates the inside of [table].
  const SlideTableView({
    super.key,
    required this.table,
    required this.style,
    required this.theme,
    this.cellLabel = defaultSlideTableCellLabel,
    this.selectedCells,
    this.editingCell,
    this.editor,
  });

  /// The table to draw.
  final TableElement table;

  /// Supplies the selection tint.
  final SlideCanvasStyle style;

  /// The theme the table's role colors and unset text styles resolve
  /// against.
  final SlideTheme theme;

  /// Names each cell for a screen reader.
  final SlideTableCellLabel cellLabel;

  /// The cells selected on the canvas, or `null` for none.
  final CellRange? selectedCells;

  /// The cell being edited, or `null`.
  final ({int row, int column})? editingCell;

  /// The in-place editor drawn in [editingCell].
  final Widget? editor;

  /// The [ValueKey] value of the cell at [row], [column] of the table [id]:
  /// `slide_table_cell_<id>_<row>_<column>`.
  static String cellKeyName(String id, int row, int column) =>
      'slide_table_cell_${id}_${row}_$column';

  /// [theme] as [row] of [table] draws its text: in a header row, text that
  /// leaves its color unset takes `TableElement.headerTextColor`.
  static SlideTheme cellTheme(TableElement table, int row, SlideTheme theme) =>
      table.isHeader(row)
          ? theme.copyWith(
              body: theme.body.copyWith(color: TableElement.headerTextColor),
            )
          : theme;

  @override
  Widget build(BuildContext context) {
    final selected = selectedCells;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var r = 0; r < table.rowCount; r++)
          for (var c = 0; c < table.columnCount; c++)
            if (!table.isCovered(r, c))
              SlideTableCellView(
                key: ValueKey(cellKeyName(table.id, r, c)),
                table: table,
                row: r,
                column: c,
                style: style,
                theme: theme,
                label: cellLabel(r, c, table.cell(r, c).plainText),
                selected: selected != null && selected.contains(r, c),
                editor: editingCell == (row: r, column: c) ? editor : null,
              ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: SlideTableBorderPainter(table, theme),
            ),
          ),
        ),
      ],
    );
  }
}
