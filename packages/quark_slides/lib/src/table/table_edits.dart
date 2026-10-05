/// The pure functions behind the table commands of
/// `SlideDocumentController`: each takes a [TableElement] and returns the
/// changed one, keeping merged areas rectangular and the columns and rows
/// adding up to the frame.
library;

import 'dart:math' as math;

import '../format/json_fields.dart';
import '../model/cell_border_preset.dart';
import '../model/cell_borders.dart';
import '../model/cell_format.dart';
import '../model/cell_range.dart';
import '../model/element_frame.dart';
import '../model/rich_text.dart';
import '../model/slide_color.dart';
import '../model/slide_element.dart';
import '../model/stroke.dart';
import '../model/slide_table_cell.dart';
import '../model/text_paragraph.dart';

/// The narrowest a column, and the shortest a row, can be made, in slide
/// units.
const minTableCellSize = 20.0;

/// A new [rows] × [columns] table filling [frame] in equal columns and
/// rows, every edge drawn with [border] (`TableElement.defaultBorder` by
/// default), with a header row and banded rows unless told otherwise.
TableElement newTable({
  required String id,
  required ElementFrame frame,
  required int rows,
  required int columns,
  Stroke? border,
  bool headerRow = true,
  bool bandedRows = true,
}) {
  _checkSize(rows, columns);
  final cell = SlideTableCell(
    borders: CellBorders.all(border ?? TableElement.defaultBorder),
  );
  return TableElement(
    id: id,
    frame: frame,
    columnWidths: List.filled(columns, frame.width / columns),
    rowHeights: List.filled(rows, frame.height / rows),
    cells: List.generate(rows, (_) => List.filled(columns, cell)),
    headerRow: headerRow,
    bandedRows: bandedRows,
  );
}

void _checkSize(int rows, int columns) {
  if (rows < 1 ||
      columns < 1 ||
      rows > TableElement.maxRows ||
      columns > TableElement.maxColumns ||
      rows * columns > TableElement.maxCells) {
    throw ArgumentError(
      'a table needs 1 to ${TableElement.maxRows} rows and 1 to '
      '${TableElement.maxColumns} columns, at most '
      '${TableElement.maxCells} cells: $rows×$columns',
    );
  }
}

/// [table] with rows and columns swapped, its frame's width and height with
/// them. Transposing twice gives [table] back; the column commands are the
/// row commands run on the transposed table.
TableElement transposeTable(TableElement table) => table.copyWith(
      frame: table.frame.copyWith(
        width: table.frame.height,
        height: table.frame.width,
      ),
      columnWidths: table.rowHeights,
      rowHeights: table.columnWidths,
      cells: [
        for (var c = 0; c < table.columnCount; c++)
          [
            for (var r = 0; r < table.rowCount; r++)
              table.cell(r, c).transposed,
          ],
      ],
    );

/// [table] with [count] blank rows inserted before row [index]
/// ([TableElement.rowCount] appends), each as tall as the row it was
/// inserted next to and taking its cells' fill, borders and anchor. The
/// table grows taller; a merge the new rows land inside grows with them.
TableElement insertTableRows(TableElement table, int index, {int count = 1}) {
  RangeError.checkValueInInterval(index, 0, table.rowCount, 'index');
  if (count < 1) return table;
  _checkSize(table.rowCount + count, table.columnCount);
  final from = index > 0 ? index - 1 : 0;
  final height = table.rowHeights[from];
  final blank = [
    for (final cell in table.cells[from])
      SlideTableCell(
          fill: cell.fill, borders: cell.borders, anchor: cell.anchor),
  ];
  final cells = [
    for (var r = 0; r < table.rowCount; r++)
      [
        for (var c = 0; c < table.columnCount; c++)
          switch (table.cell(r, c)) {
            final cell when r < index && r + cell.rowSpan > index =>
              cell.copyWith(rowSpan: cell.rowSpan + count),
            final cell => cell,
          },
      ],
  ]..insertAll(index, List.generate(count, (_) => blank));
  return table.copyWith(
    frame: table.frame.copyWith(
      height: table.frame.height + height * count,
    ),
    rowHeights: [...table.rowHeights]
      ..insertAll(index, List.filled(count, height)),
    cells: cells,
  );
}

/// [table] with [count] blank columns inserted before column [index]; see
/// [insertTableRows]. The table grows wider.
TableElement insertTableColumns(
  TableElement table,
  int index, {
  int count = 1,
}) =>
    transposeTable(
      insertTableRows(transposeTable(table), index, count: count),
    );

/// [table] without the [count] rows from [first], or `null` when that is
/// every row. The table grows shorter. A merge loses the rows deleted from
/// it; one whose first row goes moves its text to its new first row.
TableElement? deleteTableRows(TableElement table, int first, {int count = 1}) {
  RangeError.checkValidIndex(first, table.cells, 'first');
  final end = math.min(table.rowCount, first + count);
  if (end - first >= table.rowCount) return null;
  final cells = [
    for (final row in table.cells) [...row]
  ];
  for (var r = 0; r < table.rowCount; r++) {
    for (var c = 0; c < table.columnCount; c++) {
      final cell = cells[r][c];
      if (cell.rowSpan == 1) continue;
      final int lost = math.min(r + cell.rowSpan, end) - math.max(r, first);
      if (lost <= 0) continue;
      final span = cell.rowSpan - lost;
      if (span == 0) continue;
      if (r >= first) {
        // The anchor row goes: the first surviving row takes its place.
        cells[end][c] = cells[end][c].copyWith(
          paragraphs: cell.paragraphs,
          fill: cell.fill,
          anchor: cell.anchor,
          rowSpan: span,
          colSpan: cell.colSpan,
        );
      } else {
        cells[r][c] = cell.copyWith(rowSpan: span);
      }
    }
  }
  final removed =
      table.rowHeights.sublist(first, end).fold(0.0, (a, b) => a + b);
  return table.copyWith(
    frame: table.frame.copyWith(
      height: math.max(0, table.frame.height - removed),
    ),
    rowHeights: [...table.rowHeights]..removeRange(first, end),
    cells: cells..removeRange(first, end),
  );
}

/// [table] without the [count] columns from [first], or `null` when that
/// is every column; see [deleteTableRows]. The table grows narrower.
TableElement? deleteTableColumns(
  TableElement table,
  int first, {
  int count = 1,
}) {
  final deleted = deleteTableRows(transposeTable(table), first, count: count);
  return deleted == null ? null : transposeTable(deleted);
}

/// [table] with [column] made [width] wide, never under
/// [minTableCellSize]. The column to its right gives or takes the
/// difference, so the table keeps its width, as dragging the line between
/// them does; the last column changes the table's width instead.
TableElement resizeTableColumn(
  TableElement table,
  int column,
  double width,
) {
  RangeError.checkValidIndex(column, table.columnWidths, 'column');
  final widths = [...table.columnWidths];
  if (column + 1 < widths.length) {
    final pair = widths[column] + widths[column + 1];
    final low = math.min(minTableCellSize, pair / 2);
    widths[column] = width.clamp(low, pair - low);
    widths[column + 1] = pair - widths[column];
    return table.copyWith(columnWidths: widths);
  }
  widths[column] = math.max(width, minTableCellSize);
  return table.copyWith(
    frame: table.frame.copyWith(
      width: table.frame.width - table.columnWidths[column] + widths[column],
    ),
    columnWidths: widths,
  );
}

/// [table] with [row] made [height] tall, never under [minTableCellSize];
/// the table grows or shrinks with it. A row is never shorter than its
/// text once the controller refits it.
TableElement resizeTableRow(TableElement table, int row, double height) {
  RangeError.checkValidIndex(row, table.rowHeights, 'row');
  final heights = [...table.rowHeights];
  heights[row] = math.max(height, minTableCellSize);
  return table.copyWith(
    frame: table.frame.copyWith(
      height: table.frame.height - table.rowHeights[row] + heights[row],
    ),
    rowHeights: heights,
  );
}

/// [table] with the text of the cell at [row], [column] — its merge
/// anchor's — replaced by [paragraphs].
TableElement setTableCellText(
  TableElement table,
  int row,
  int column,
  List<TextParagraph> paragraphs,
) {
  _checkCell(table, row, column);
  final at = table.anchorOf(row, column);
  return _replaceCell(
    table,
    at.row,
    at.column,
    table
        .cell(at.row, at.column)
        .copyWith(paragraphs: List.unmodifiable(paragraphs)),
  );
}

/// [table] with [format] applied to every cell in [range], grown to take in
/// any merge it cuts through. See [CellFormat].
TableElement formatTableCells(
  TableElement table,
  CellRange range,
  CellFormat format,
) {
  _checkRange(table, range);
  final area = table.expandToMerges(range);
  final cells = [
    for (final row in table.cells) [...row]
  ];
  for (var r = area.top; r <= area.bottom; r++) {
    for (var c = area.left; c <= area.right; c++) {
      if (table.isCovered(r, c)) continue;
      var cell = cells[r][c];
      final text = format.text;
      if (text != null) {
        final box = formatTextBox(table.cellTextBox(r, c), text);
        cell = cell.copyWith(paragraphs: box.paragraphs, anchor: box.anchor);
      }
      cells[r][c] = cell.copyWith(fill: format.fill);
    }
  }
  final preset = format.borders;
  if (preset != null) {
    final stroke = preset == CellBorderPreset.none
        ? null
        : format.borderStroke ?? TableElement.defaultBorder;
    _drawBorders(cells, area, preset, stroke);
  }
  return table.copyWith(cells: cells);
}

/// Sets the edges of [area] that [preset] names to [stroke], on both cells
/// that share each one.
void _drawBorders(
  List<List<SlideTableCell>> cells,
  CellRange area,
  CellBorderPreset preset,
  Stroke? stroke,
) {
  bool horizontal(int boundary) => switch (preset) {
        CellBorderPreset.all || CellBorderPreset.none => true,
        CellBorderPreset.outside =>
          boundary == area.top || boundary == area.bottom + 1,
        CellBorderPreset.inside ||
        CellBorderPreset.insideHorizontal =>
          boundary != area.top && boundary != area.bottom + 1,
        CellBorderPreset.top => boundary == area.top,
        CellBorderPreset.bottom => boundary == area.bottom + 1,
        _ => false,
      };
  bool vertical(int boundary) => switch (preset) {
        CellBorderPreset.all || CellBorderPreset.none => true,
        CellBorderPreset.outside =>
          boundary == area.left || boundary == area.right + 1,
        CellBorderPreset.inside ||
        CellBorderPreset.insideVertical =>
          boundary != area.left && boundary != area.right + 1,
        CellBorderPreset.left => boundary == area.left,
        CellBorderPreset.right => boundary == area.right + 1,
        _ => false,
      };
  void side(int r, int c, CellSide side) {
    if (r < 0 || c < 0 || r >= cells.length || c >= cells[r].length) return;
    final cell = cells[r][c];
    cells[r][c] = cell.copyWith(borders: cell.borders.withSide(side, stroke));
  }

  for (var b = area.top; b <= area.bottom + 1; b++) {
    if (!horizontal(b)) continue;
    for (var c = area.left; c <= area.right; c++) {
      side(b - 1, c, CellSide.bottom);
      side(b, c, CellSide.top);
    }
  }
  for (var b = area.left; b <= area.right + 1; b++) {
    if (!vertical(b)) continue;
    for (var r = area.top; r <= area.bottom; r++) {
      side(r, b - 1, CellSide.right);
      side(r, b, CellSide.left);
    }
  }
}

/// [table] with the cells of [range] — grown to take in any merge it cuts
/// through — merged into one, anchored at its top-left cell. The text of
/// every cell that has any is joined into the anchor, in reading order,
/// and the covered cells are emptied. A single cell is left alone.
TableElement mergeTableCells(TableElement table, CellRange range) {
  _checkRange(table, range);
  final area = table.expandToMerges(range);
  if (area.isSingle) return table;
  final cells = [
    for (final row in table.cells) [...row]
  ];
  final paragraphs = <TextParagraph>[];
  for (var r = area.top; r <= area.bottom; r++) {
    for (var c = area.left; c <= area.right; c++) {
      final cell = cells[r][c];
      if (cell.plainText.isNotEmpty) paragraphs.addAll(cell.paragraphs);
      cells[r][c] = cell.copyWith(
        paragraphs: const [],
        rowSpan: 1,
        colSpan: 1,
      );
    }
  }
  final anchor = table.cell(area.top, area.left);
  cells[area.top][area.left] = anchor.copyWith(
    paragraphs: paragraphs.isEmpty ? anchor.paragraphs : paragraphs,
    rowSpan: area.rowCount,
    colSpan: area.columnCount,
  );
  return table.copyWith(cells: cells);
}

/// [table] with every merge touching [range] split back into its cells.
/// The text stays in the anchor; the cells it covered come back empty.
TableElement unmergeTableCells(TableElement table, CellRange range) {
  _checkRange(table, range);
  final area = table.expandToMerges(range);
  final cells = [
    for (final row in table.cells) [...row]
  ];
  for (var r = area.top; r <= area.bottom; r++) {
    for (var c = area.left; c <= area.right; c++) {
      if (cells[r][c].isMerged) {
        cells[r][c] = cells[r][c].copyWith(rowSpan: 1, colSpan: 1);
      }
    }
  }
  return table.copyWith(cells: cells);
}

/// [table] with its header row, banded rows and header [accent] changed;
/// what is left out is kept.
TableElement styleTable(
  TableElement table, {
  bool? headerRow,
  bool? bandedRows,
  SlideColor? accent,
}) =>
    table.copyWith(
      headerRow: headerRow,
      bandedRows: bandedRows,
      accent: accent,
    );

/// [table] with every row grown, never shrunk, to fit its cells' text as
/// [measure] lays it out (see `TableElement.cellTextBox`), plus the cells'
/// padding. A merge spanning rows that needs more room grows its last row.
/// The table grows taller with its rows.
TableElement fitTableRows(
  TableElement table,
  double Function(TextBox box) measure,
) {
  final heights = [...table.rowHeights];
  final spans = <(int, int, double)>[];
  for (var r = 0; r < table.rowCount; r++) {
    for (var c = 0; c < table.columnCount; c++) {
      if (table.isCovered(r, c)) continue;
      final cell = table.cell(r, c);
      if (cell.paragraphs.isEmpty) continue;
      final need =
          measure(table.cellTextBox(r, c)) + 2 * TableElement.cellPaddingY;
      if (cell.rowSpan == 1) {
        if (need > heights[r] + 1e-6) heights[r] = need;
      } else {
        spans.add((r, cell.rowSpan, need));
      }
    }
  }
  for (final (row, span, need) in spans) {
    final last = math.min(heights.length, row + span) - 1;
    final have = heights.sublist(row, last + 1).fold(0.0, (a, b) => a + b);
    if (need > have + 1e-6) heights[last] += need - have;
  }
  if (listEquals(heights, table.rowHeights)) return table;
  return table.copyWith(
    frame: table.frame.copyWith(
      height: heights.fold<double>(0, (a, b) => a + b),
    ),
    rowHeights: heights,
  );
}

TableElement _replaceCell(
  TableElement table,
  int row,
  int column,
  SlideTableCell cell,
) =>
    table.copyWith(
      cells: [
        for (var r = 0; r < table.rowCount; r++)
          r == row ? ([...table.cells[r]]..[column] = cell) : table.cells[r],
      ],
    );

void _checkCell(TableElement table, int row, int column) {
  RangeError.checkValidIndex(row, table.cells, 'row');
  RangeError.checkValidIndex(column, table.columnWidths, 'column');
}

void _checkRange(TableElement table, CellRange range) {
  _checkCell(table, range.top, range.left);
  _checkCell(table, range.bottom, range.right);
}
