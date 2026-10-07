part of 'slide_element.dart';

/// A grid of [cells], [columnWidths] wide and [rowHeights] tall in slide
/// units, each cell holding rich text with its own fill and borders.
///
/// The columns add up to the frame's width and the rows to its height:
/// resizing the table through [withFrame] scales every column and row in
/// proportion, so moving, resizing and rotating it with the ordinary
/// element commands just works. A row grows to fit its text, as a growing
/// text box does, whenever a command changes the table.
///
/// [cells] is always a full `rows × columns` grid. A cell whose
/// `SlideTableCell.rowSpan` or `SlideTableCell.colSpan` is above 1 is the anchor of a
/// merged area, and the cells it covers are kept but not drawn (see
/// [anchorOf]). Merged areas are rectangles and never overlap.
///
/// With [headerRow] the first row is filled with [accent] and its text set
/// in the theme's background color; with [bandedRows] every other body row
/// is filled with the theme's `background2`. A cell's own fill wins over
/// both (see [fillAt]).
///
/// In `.qslide`:
///
/// ```json
/// {"id": "t1", "type": "table",
///  "frame": {"x": 160, "y": 200, "width": 600, "height": 160},
///  "columns": [300, 300], "rows": [80, 80],
///  "headerRow": true, "bandedRows": true,
///  "cells": [[{"paragraphs": [{"runs": [{"text": "Region"}]}]}, {}],
///            [{}, {}]]}
/// ```
///
/// A file whose `rows` or `columns` exceed [maxRows], [maxColumns] or
/// [maxCells] in all is refused with a `QslideFormatException`: a table
/// is drawn cell by cell, and a hostile file should not be able to make
/// that cost unbounded.
class TableElement extends SlideElement {
  /// Creates a table. [cells] must have one row per entry of [rowHeights],
  /// each with one cell per entry of [columnWidths].
  TableElement({
    required super.id,
    required super.frame,
    required List<double> columnWidths,
    required List<double> rowHeights,
    required List<List<SlideTableCell>> cells,
    this.headerRow = false,
    this.bandedRows = false,
    this.accent = defaultAccent,
    super.extra,
  })  : assert(cells.length == rowHeights.length),
        assert(cells.every((row) => row.length == columnWidths.length)),
        columnWidths = List.unmodifiable(columnWidths),
        rowHeights = List.unmodifiable(rowHeights),
        cells = List.unmodifiable([
          for (final row in cells) List<SlideTableCell>.unmodifiable(row),
        ]);

  /// The `type` discriminator, `table`.
  static const typeName = 'table';

  /// The most rows a table may have.
  static const maxRows = 500;

  /// The most columns a table may have.
  static const maxColumns = 100;

  /// The most cells a table may have, rows times columns.
  static const maxCells = 5000;

  /// The header row's fill unless set: the theme's first accent.
  static const defaultAccent = SlideColor.theme(ThemeColor.accent1);

  /// The fill of every other body row of a banded table.
  static const bandColor = SlideColor.theme(ThemeColor.background2);

  /// The line a new table draws along every cell's edges: the theme's
  /// secondary text color, 2 units wide.
  static final defaultBorder = Stroke(
    color: const SlideColor.theme(ThemeColor.text2),
    width: 2,
  );

  /// The color of a header row's text that leaves its own unset.
  static const headerTextColor = SlideColor.theme(ThemeColor.background);

  /// The space between a cell's edges and its text, left and right, in
  /// slide units.
  static const cellPaddingX = 14.0;

  /// The space between a cell's edges and its text, above and below, in
  /// slide units.
  static const cellPaddingY = 8.0;

  static const _known = {
    'id',
    'type',
    'frame',
    'columns',
    'rows',
    'cells',
    'headerRow',
    'bandedRows',
    'accent',
  };

  /// The width of each column, left to right, in slide units.
  final List<double> columnWidths;

  /// The height of each row, top to bottom, in slide units.
  final List<double> rowHeights;

  /// The cells, a list per row, top to bottom.
  final List<List<SlideTableCell>> cells;

  /// Whether the first row is a header, filled with [accent].
  final bool headerRow;

  /// Whether every other body row is filled with [bandColor].
  final bool bandedRows;

  /// The header row's fill.
  final SlideColor accent;

  /// How many rows the table has.
  int get rowCount => rowHeights.length;

  /// How many columns the table has.
  int get columnCount => columnWidths.length;

  /// The cell at [row], [column], covered by a merge or not.
  SlideTableCell cell(int row, int column) => cells[row][column];

  /// Whether [row] is the header row.
  bool isHeader(int row) => headerRow && row == 0;

  /// The left edge of [column], in table-local slide units; [columnCount]
  /// gives the right edge of the last.
  double columnStart(int column) {
    var x = 0.0;
    for (var c = 0; c < column; c++) {
      x += columnWidths[c];
    }
    return x;
  }

  /// The top edge of [row], in table-local slide units; [rowCount] gives
  /// the bottom edge of the last.
  double rowStart(int row) {
    var y = 0.0;
    for (var r = 0; r < row; r++) {
      y += rowHeights[r];
    }
    return y;
  }

  /// The anchor of the merged area covering [row], [column], or the cell
  /// itself when no merge covers it.
  ({int row, int column}) anchorOf(int row, int column) =>
      _anchors[row][column];

  /// Every cell's merge anchor, worked out once.
  late final List<List<({int row, int column})>> _anchors = () {
    final anchors = [
      for (var r = 0; r < rowCount; r++)
        [for (var c = 0; c < columnCount; c++) (row: r, column: c)],
    ];
    for (var r = 0; r < rowCount; r++) {
      for (var c = 0; c < columnCount; c++) {
        final cell = cells[r][c];
        if (!cell.isMerged || anchors[r][c] != (row: r, column: c)) continue;
        for (var i = r; i < math.min(rowCount, r + cell.rowSpan); i++) {
          for (var j = c; j < math.min(columnCount, c + cell.colSpan); j++) {
            anchors[i][j] = (row: r, column: c);
          }
        }
      }
    }
    return anchors;
  }();

  /// Whether [row], [column] is hidden under another cell's merge.
  bool isCovered(int row, int column) {
    final anchor = anchorOf(row, column);
    return anchor.row != row || anchor.column != column;
  }

  /// The cells the merge anchored at [row], [column] spans — the one cell
  /// when it is not merged — clipped to the grid.
  CellRange areaOf(int row, int column) {
    final anchor = anchorOf(row, column);
    final cell = cells[anchor.row][anchor.column];
    return CellRange(
      top: anchor.row,
      left: anchor.column,
      bottom: math.min(rowCount, anchor.row + cell.rowSpan) - 1,
      right: math.min(columnCount, anchor.column + cell.colSpan) - 1,
    );
  }

  /// [range] grown until it cuts through no merged area.
  CellRange expandToMerges(CellRange range) {
    var result = range;
    var grown = true;
    while (grown) {
      grown = false;
      for (var r = result.top; r <= result.bottom; r++) {
        for (var c = result.left; c <= result.right; c++) {
          final next = result.union(areaOf(r, c));
          if (next != result) {
            result = next;
            grown = true;
          }
        }
      }
    }
    return result;
  }

  /// The box of the cell at [row], [column] — the whole merged area when it
  /// is merged or covered — in table-local slide units.
  ({double x, double y, double width, double height}) cellBox(
    int row,
    int column,
  ) {
    final area = areaOf(row, column);
    final x = columnStart(area.left);
    final y = rowStart(area.top);
    return (
      x: x,
      y: y,
      width: columnStart(area.right + 1) - x,
      height: rowStart(area.bottom + 1) - y,
    );
  }

  /// The anchor of the cell under the table-local point [x], [y], or
  /// `null` outside the table.
  ({int row, int column})? cellAt(double x, double y) {
    if (x < 0 || y < 0 || x > frame.width || y > frame.height) return null;
    int index(List<double> sizes, double at) {
      var edge = 0.0;
      for (var i = 0; i < sizes.length; i++) {
        edge += sizes[i];
        if (at < edge) return i;
      }
      return sizes.length - 1;
    }

    if (rowCount == 0 || columnCount == 0) return null;
    return anchorOf(index(rowHeights, y), index(columnWidths, x));
  }

  /// The fill drawn under the cell at [row], [column]: its merge anchor's
  /// own fill, or [accent] in the header row, or [bandColor] on every
  /// other body row when the table is banded, or `null` for none.
  SlideColor? fillAt(int row, int column) {
    final anchor = anchorOf(row, column);
    final own = cells[anchor.row][anchor.column].fill;
    if (own != null) return own;
    if (isHeader(anchor.row)) return accent;
    final body = anchor.row - (headerRow ? 1 : 0);
    return bandedRows && body.isOdd ? bandColor : null;
  }

  /// The line along the top of the cell at [row], [column] — the bottom of
  /// the table when [row] is [rowCount] — or `null` for none. The cell
  /// above wins where it has a line; inside a merged area there is none.
  Stroke? edgeAbove(int row, int column) {
    final above = row > 0 ? cells[row - 1][column] : null;
    final below = row < rowCount ? cells[row][column] : null;
    if (above != null &&
        below != null &&
        anchorOf(row - 1, column) == anchorOf(row, column)) {
      return null;
    }
    return above?.borders.bottom ?? below?.borders.top;
  }

  /// The line along the left of the cell at [row], [column] — the right of
  /// the table when [column] is [columnCount] — or `null` for none. The
  /// cell to the left wins where it has a line; inside a merged area there
  /// is none.
  Stroke? edgeBefore(int row, int column) {
    final before = column > 0 ? cells[row][column - 1] : null;
    final after = column < columnCount ? cells[row][column] : null;
    if (before != null &&
        after != null &&
        anchorOf(row, column - 1) == anchorOf(row, column)) {
      return null;
    }
    return before?.borders.right ?? after?.borders.left;
  }

  /// The text of the cell at [row], [column] — its merge anchor's — as a
  /// [TextBox] with this table's id, framed in table-local slide units
  /// inside the cell's padding: what draws, measures, edits and formats
  /// it.
  TextBox cellTextBox(int row, int column) {
    final anchor = anchorOf(row, column);
    final cell = cells[anchor.row][anchor.column];
    final box = cellBox(anchor.row, anchor.column);
    return TextBox(
      id: id,
      frame: ElementFrame(
        x: box.x + cellPaddingX,
        y: box.y + cellPaddingY,
        width: math.max(0, box.width - 2 * cellPaddingX),
        height: math.max(0, box.height - 2 * cellPaddingY),
      ),
      paragraphs: cell.paragraphs,
      anchor: cell.anchor,
      autoFit: TextAutoFit.fixed,
    );
  }

  /// Every cell's text, a line per row with cells separated by tabs;
  /// covered cells are left out.
  String get plainText => [
        for (var r = 0; r < rowCount; r++)
          [
            for (var c = 0; c < columnCount; c++)
              if (!isCovered(r, c)) cells[r][c].plainText.replaceAll('\n', ' '),
          ].join('\t'),
      ].join('\n');

  @override
  String get type => typeName;

  @override
  JsonMap _fieldsToJson() => {
        'columns': [for (final w in columnWidths) jsonNumber(w)],
        'rows': [for (final h in rowHeights) jsonNumber(h)],
        if (headerRow) 'headerRow': true,
        if (bandedRows) 'bandedRows': true,
        if (accent != defaultAccent) 'accent': accent.toHex(),
        'cells': [
          for (final row in cells) [for (final cell in row) cell.toJson()],
        ],
      };

  static TableElement _fromJson(
    JsonMap json,
    String id,
    ElementFrame frame,
    String path,
  ) {
    List<double> sizes(String key) {
      final list = optionalList(json, key, path);
      return [
        for (var i = 0; i < list.length; i++)
          switch (list[i]) {
            final num n when n.isFinite && n > 0 => n.toDouble(),
            _ => throw QslideFormatException(
                'expected a positive number',
                path: '$path.$key[$i]',
              ),
          },
      ];
    }

    final columns = sizes('columns');
    final rows = sizes('rows');
    if (rows.isEmpty ||
        columns.isEmpty ||
        rows.length > maxRows ||
        columns.length > maxColumns ||
        rows.length * columns.length > maxCells) {
      throw QslideFormatException(
        'a table needs 1 to $maxRows rows and 1 to $maxColumns columns, '
        'at most $maxCells cells',
        path: path,
      );
    }
    final grid = optionalList(json, 'cells', path);
    if (grid.length != rows.length) {
      throw QslideFormatException(
        'expected ${rows.length} rows of cells',
        path: '$path.cells',
      );
    }
    final cells = [
      for (var r = 0; r < grid.length; r++)
        () {
          final row = asList(grid[r], '$path.cells[$r]');
          if (row.length != columns.length) {
            throw QslideFormatException(
              'expected ${columns.length} cells',
              path: '$path.cells[$r]',
            );
          }
          return [
            for (var c = 0; c < row.length; c++)
              SlideTableCell.fromJson(row[c], '$path.cells[$r][$c]'),
          ];
        }(),
    ];
    final accent = optionalString(json, 'accent', path);
    return TableElement(
      id: id,
      frame: frame,
      columnWidths: columns,
      rowHeights: rows,
      cells: normalizedSpans(cells),
      headerRow: optionalBool(json, 'headerRow', path, false),
      bandedRows: optionalBool(json, 'bandedRows', path, false),
      accent: accent == null
          ? defaultAccent
          : SlideColor.parse(accent, path: '$path.accent'),
      extra: unknownFields(json, _known),
      // The grid is read as written; the frame is what the table fills.
    )._fittedToFrame();
  }

  /// [cells] with every merge clipped to the grid and any merge that would
  /// overlap an earlier one (in reading order) undone, so the areas are
  /// rectangles that never overlap.
  static List<List<SlideTableCell>> normalizedSpans(
      List<List<SlideTableCell>> cells) {
    final rows = cells.length;
    final columns = rows == 0 ? 0 : cells.first.length;
    final taken = List.generate(rows, (_) => List.filled(columns, false));
    final result = [
      for (final row in cells) [...row]
    ];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        var cell = result[r][c];
        if (taken[r][c]) {
          if (cell.isMerged) {
            result[r][c] = cell.copyWith(rowSpan: 1, colSpan: 1);
          }
          continue;
        }
        var rowSpan = math.min(cell.rowSpan, rows - r);
        var colSpan = math.min(cell.colSpan, columns - c);
        var free = true;
        for (var i = r; i < r + rowSpan && free; i++) {
          for (var j = c; j < c + colSpan; j++) {
            if (taken[i][j]) free = false;
          }
        }
        if (!free) rowSpan = colSpan = 1;
        if (rowSpan != cell.rowSpan || colSpan != cell.colSpan) {
          cell =
              result[r][c] = cell.copyWith(rowSpan: rowSpan, colSpan: colSpan);
        }
        for (var i = r; i < r + rowSpan; i++) {
          for (var j = c; j < c + colSpan; j++) {
            taken[i][j] = true;
          }
        }
      }
    }
    return result;
  }

  /// This table with its columns and rows scaled to fill its frame.
  TableElement _fittedToFrame() {
    final columns = _scaled(columnWidths, frame.width);
    final rows = _scaled(rowHeights, frame.height);
    if (identical(columns, columnWidths) && identical(rows, rowHeights)) {
      return this;
    }
    return copyWith(columnWidths: columns, rowHeights: rows);
  }

  /// [sizes] scaled to add up to [total]; [sizes] itself when they already
  /// do.
  static List<double> _scaled(List<double> sizes, double total) {
    final sum = sizes.fold(0.0, (a, b) => a + b);
    if (sum <= 0 || (sum - total).abs() < 1e-9) return sizes;
    final factor = total / sum;
    return [for (final s in sizes) s * factor];
  }

  /// Returns a copy with the given fields replaced. The frame is kept as
  /// given; to change the size, pass [frame] with [columnWidths] and
  /// [rowHeights] that add up to it, or call [withFrame].
  TableElement copyWith({
    String? id,
    ElementFrame? frame,
    List<double>? columnWidths,
    List<double>? rowHeights,
    List<List<SlideTableCell>>? cells,
    bool? headerRow,
    bool? bandedRows,
    SlideColor? accent,
  }) =>
      TableElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        columnWidths: columnWidths ?? this.columnWidths,
        rowHeights: rowHeights ?? this.rowHeights,
        cells: cells ?? this.cells,
        headerRow: headerRow ?? this.headerRow,
        bandedRows: bandedRows ?? this.bandedRows,
        accent: accent ?? this.accent,
        extra: extra,
      );

  /// Returns a copy with [frame] replaced, every column and row scaled in
  /// proportion to the new width and height.
  @override
  TableElement withFrame(ElementFrame frame) =>
      copyWith(frame: frame)._fittedToFrame();

  @override
  TableElement withId(String id) => copyWith(id: id);

  @override
  bool operator ==(Object other) =>
      other is TableElement &&
      other.id == id &&
      other.frame == frame &&
      other.headerRow == headerRow &&
      other.bandedRows == bandedRows &&
      other.accent == accent &&
      listEquals(other.columnWidths, columnWidths) &&
      listEquals(other.rowHeights, rowHeights) &&
      listEquals(
        other.cells,
        cells,
        (a, b) => listEquals<SlideTableCell>(a, b),
      ) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        id,
        frame,
        Object.hashAll(columnWidths),
        Object.hashAll(rowHeights),
        Object.hashAll(cells.map(Object.hashAll)),
        headerRow,
        bandedRows,
        accent,
        jsonHash(extra),
      );
}
