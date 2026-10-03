import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ValueNotifier, mapEquals;
import 'package:flutter/material.dart' show Color;
import 'package:flutter/painting.dart'
    show FontStyle, FontWeight, TextPainter, TextSpan, TextStyle;
import 'package:quark_formula/evaluation/evaluation.dart';

import '../../data_table.dart';
import 'cell/heading/heading_cells.dart'
    show kDefaultColumnWidth, kDefaultRowHeight, kMinColumnWidth, kMinRowHeight;
import 'cell_range.dart';
import 'column_filter.dart';
import 'data_sheet_selection.dart';
import 'format/format_cell_value.dart';
import 'formula/formula_references.dart';
import 'formula/formula_text_editing_controller.dart';

// ---------------------------------------------------------------------------
// Internal snapshot used for undo / redo.
// ---------------------------------------------------------------------------

class _TableSnapshot {
  final List<List<String>> cells; // [row][col] as strings
  final List<double> columnWidths;
  final List<double> rowHeights;
  final int frozenRows;
  final int frozenColumns;
  final Map<int, ColumnFilter> filters;
  final List<bool> hidden;
  final Map<(int, int), CellFormat> formats;

  _TableSnapshot(
    this.cells,
    this.columnWidths,
    this.rowHeights,
    this.frozenRows,
    this.frozenColumns,
    this.filters,
    this.hidden,
    this.formats,
  );

  factory _TableSnapshot.capture(DataSheetController c) {
    return _TableSnapshot(
      List.generate(
        c._rows.length,
        (r) => c._rows[r].value.map((cell) => cell.value.toString()).toList(),
      ),
      List<double>.from(c.columnWidths),
      List<double>.from(c.rowHeights),
      c._frozenRows,
      c._frozenColumns,
      Map<int, ColumnFilter>.from(c._filters),
      List<bool>.from(c._hidden),
      Map<(int, int), CellFormat>.from(c._formats),
    );
  }

  /// Restore this snapshot into [c]. Callers must call [c.notifyListeners]
  /// afterward if needed.
  void restore(DataSheetController c) {
    for (final row in c._rows) {
      row.dispose();
    }
    c._rows.clear();
    c.table.rows.clear();
    for (final rowData in cells) {
      final rowCells = rowData.map((v) => DataCell(v)).toList();
      c.table.rows.add(DataRow(List<DataCell>.from(rowCells)));
      c._rows.add(ValueNotifier<List<DataCell>>(List<DataCell>.from(rowCells)));
    }
    c.columnWidths = List<double>.from(columnWidths);
    c.rowHeights = List<double>.from(rowHeights);
    c._frozenRows = frozenRows;
    c._frozenColumns = frozenColumns;
    c._filters = Map<int, ColumnFilter>.from(filters);
    c._hidden = List<bool>.from(hidden);
    c._formats = Map<(int, int), CellFormat>.from(formats);
  }
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// The state behind a `DataSheet`: the table, column widths and row heights, the frozen header rows and columns,
/// the column filters and the rows they hide, the evaluated value of each cell, and undo and redo.
///
/// Sizes are pixels. [layoutToJson] and [DataSheetController.fromLayoutJson] are the layout's saved form, and
/// loading tolerates anything older or broken: missing keys, a legacy `columnFlex` list, lists of the wrong
/// length, and values that are not numbers all fall back to defaults.
///
/// Filters hide rows without deleting them: row indexes never change, and range operations (copy, clear, paste,
/// fill, delete row) skip hidden rows. Frozen rows are headers and are never hidden. Filters apply when they are
/// set, so a row edited to a value the filter excludes stays visible until the filters next change.
///
/// Cell formats ([formatAt], [applyFormat]) are kept sparsely, by cell, and follow their cells: inserting, deleting,
/// duplicating and sorting rows and columns move them, filters leave them alone, and a copy pasted back into the same
/// sheet carries them. A number format changes only [formattedValueAt]; the stored value, [displayValueAt], formulas,
/// sorting and filters all read the raw value.
class DataSheetController extends ChangeNotifier {
  final DataTable table;
  final List<ValueNotifier<List<DataCell>>> _rows;

  /// Per-column pixel widths. Length equals [colCount].
  List<double> columnWidths;

  /// Per-row pixel heights. Length equals [rowCount].
  List<double> rowHeights;

  int _frozenRows;
  int _frozenColumns;

  /// Filters by column index; only active filters are kept.
  Map<int, ColumnFilter> _filters;

  /// Which rows the filters hid when they were last applied, by row index.
  /// Rows past its end are visible.
  List<bool> _hidden = [];

  /// [visibleRows], built on first read after a change.
  List<int>? _visibleRows;

  /// Every cell's format that is not [CellFormat.plain], by (row, col).
  Map<(int, int), CellFormat> _formats;

  /// The text the last [copyRange] produced and the formats of the cells it
  /// came from, so pasting that same text back carries them.
  ({String tsv, List<List<CellFormat>> formats})? _copied;

  /// How many rows, from the top, stay put while the grid scrolls vertically.
  int get frozenRows => _frozenRows;

  /// How many columns, from the left, stay put while the grid scrolls
  /// horizontally.
  int get frozenColumns => _frozenColumns;

  /// Selection state shared between the sheet view and the control bar.
  final DataSheetSelectionModel selection = DataSheetSelectionModel();

  /// Overlay of formula-evaluated values, keyed by (row, col).
  /// Only formula cells appear here; literal cells are absent.
  Map<(int, int), FormulaValue> _computedValues = {};

  /// The color of each cell the formula being edited, or the selected
  /// formula cell, refers to. Kept current by [notifyListeners] and by edits
  /// to [activeCellEditingController].
  Map<(int, int), Color> _refColors = const {};

  /// Shared [TextEditingController] for the currently active (in-edit) cell.
  /// Both the [DataSheet] cell editor and [DataSheetFormulaBar] use this
  /// single controller so they remain in sync without extra bridging logic.
  /// It colors a formula's references the way [activeRefColors] outlines
  /// their cells.
  final FormulaTextEditingController activeCellEditingController =
      FormulaTextEditingController();

  final List<_TableSnapshot> _undoStack = [];
  final List<_TableSnapshot> _redoStack = [];

  static const int _maxUndoDepth = 100;

  DataSheetController._(
    this.table,
    this._rows,
    this.columnWidths,
    this.rowHeights,
    this._frozenRows,
    this._frozenColumns,
    this._filters,
    this._formats,
  ) {
    selection.addListener(_onSelectionChanged);
    activeCellEditingController.addListener(_onEditingTextChanged);
    _recompute();
    _refColors = _computeRefColors();
    _applyFilters();
  }

  void _onSelectionChanged() => notifyListeners();

  // -------------------------------------------------------------------------
  // Formula evaluation
  // -------------------------------------------------------------------------

  /// Re-evaluates all formula cells in the sheet and updates [_computedValues].
  /// Called automatically after every mutation.
  void _recompute() {
    _computedValues = DataSheetInterpreter().interpretSheet(
      rowCount,
      colCount,
      (r, c) => cellAt(r, c).value.toString(),
    );
    _visibleRows = null;
  }

  /// Returns the display value for a cell.
  ///
  /// For formula cells (raw value starts with `=`) this is the computed result
  /// from [_computedValues]. For literal cells this is the raw string.
  String displayValueAt(int row, int col) {
    final computed = _computedValues[(row, col)];
    if (computed != null) return _formatFormulaValue(computed);
    return cellAt(row, col).value.toString();
  }

  /// Returns true if the cell at [row],[col] evaluated to an error.
  bool isCellError(int row, int col) =>
      _computedValues[(row, col)] is ErrorValue;

  /// The error the formula at [row],[col] evaluated to, with its code
  /// (`#DIV/0!`) and the message saying why, or null when it is not one.
  ErrorValue? errorAt(int row, int col) =>
      switch (_computedValues[(row, col)]) {
        final ErrorValue error => error,
        _ => null,
      };

  /// The color of each cell referenced by the formula being edited, keyed by
  /// (row, col). With no edit in progress, the references of the selected
  /// cell's formula. Each color matches the reference's text in the editor:
  /// both come from [formulaReferences].
  Map<(int, int), Color> get activeRefColors => _refColors;

  Map<(int, int), Color> _computeRefColors() {
    final r = selection.contextRow;
    final c = selection.contextCol;
    final formula = selection.hasActiveCell
        ? activeCellEditingController.text
        : r >= 0 && c >= 0 && r < rowCount && c < colCount
            ? cellAt(r, c).value.toString()
            : '';
    return formulaReferenceCellColors(
      formula,
      rowCount: rowCount,
      colCount: colCount,
    );
  }

  void _onEditingTextChanged() {
    final colors = _computeRefColors();
    if (mapEquals(colors, _refColors)) return;
    _refColors = colors;
    super.notifyListeners();
  }

  /// Notifies listeners after bringing [activeRefColors] up to date.
  @override
  void notifyListeners() {
    _refColors = _computeRefColors();
    super.notifyListeners();
  }

  static String _formatFormulaValue(FormulaValue v) => switch (v) {
        NumberValue(:final value) => value == value.truncateToDouble()
            ? value.toInt().toString()
            : value.toString(),
        StringValue(:final value) => value,
        BoolValue(:final value) => value ? 'TRUE' : 'FALSE',
        ErrorValue(:final code) => code,
      };

  /// A controller over [table].
  ///
  /// [columnWidths] and [rowHeights] are pixels, fitted to the table: a
  /// missing entry gets the default, an extra one is dropped, a value that is
  /// not finite gets the default, and one under the minimum is raised to it.
  /// [columnFlex] is the flex factor layout sheets used before pixel widths;
  /// each factor becomes that many default widths, and only when
  /// [columnWidths] is absent. [frozenRows] and [frozenColumns] are clamped to
  /// the table. [filters] maps a column index to its filter; entries for
  /// columns the table lacks, and inactive filters, are dropped. [formats]
  /// maps a (row, col) to its format; cells outside the table and plain
  /// formats are dropped.
  factory DataSheetController.fromTable(
    DataTable table, {
    List<double>? columnWidths,
    List<double>? rowHeights,
    List<num>? columnFlex,
    int frozenRows = 0,
    int frozenColumns = 0,
    Map<int, ColumnFilter> filters = const {},
    Map<(int, int), CellFormat> formats = const {},
  }) {
    final rows = table.rows
        .map((r) => ValueNotifier<List<DataCell>>(List<DataCell>.from(r.cells)))
        .toList();
    final colCount = table.rows.isNotEmpty ? table.rows.first.cells.length : 0;
    final rowCount = table.rows.length;
    final widths = columnWidths ??
        columnFlex?.map((f) => f * kDefaultColumnWidth).toList();
    return DataSheetController._(
      table,
      rows,
      _fitSizes(widths, colCount, kDefaultColumnWidth, kMinColumnWidth),
      _fitSizes(rowHeights, rowCount, kDefaultRowHeight, kMinRowHeight),
      frozenRows.clamp(0, rowCount),
      frozenColumns.clamp(0, colCount),
      {
        for (final MapEntry(key: col, value: filter) in filters.entries)
          if (col >= 0 && col < colCount && filter.isActive) col: filter,
      },
      {
        for (final MapEntry(key: (r, c), value: format) in formats.entries)
          if (r >= 0 && r < rowCount && c >= 0 && c < colCount)
            if (!format.isPlain) (r, c): format,
      },
    );
  }

  /// A controller over [table] with the layout saved by [layoutToJson].
  ///
  /// [json] is usually a whole `.qsheet` tab; keys other than the layout's are
  /// ignored. Sheets saved before a key existed, or with a value of the wrong
  /// type, load with the default for it.
  factory DataSheetController.fromLayoutJson(
    DataTable table,
    Map<String, dynamic>? json,
  ) {
    List<double>? numbers(Object? value) => value is List
        ? [for (final v in value) v is num ? v.toDouble() : double.nan]
        : null;
    int count(Object? value) => value is int ? value : 0;
    final filters = json?['filters'];
    final formats = json?['formats'];
    return DataSheetController.fromTable(
      table,
      columnWidths: numbers(json?['columnWidths']),
      rowHeights: numbers(json?['rowHeights']),
      columnFlex: numbers(json?['columnFlex']),
      frozenRows: count(json?['frozenRows']),
      frozenColumns: count(json?['frozenColumns']),
      filters: {
        if (filters is List)
          for (final entry in filters)
            if (entry is Map && entry['column'] is int)
              entry['column'] as int: ColumnFilter.fromJson(entry)!,
      },
      formats: {
        if (formats is List)
          for (final entry in formats)
            if (entry is Map && entry['row'] is int && entry['col'] is int)
              (entry['row'] as int, entry['col'] as int):
                  CellFormat.fromJson(entry),
      },
    );
  }

  /// The sheet's layout in the form [DataSheetController.fromLayoutJson]
  /// reads: pixel sizes, the frozen counts, the column filters, and the cell
  /// formats (a list of `{row, col, ...format}`, one per formatted cell).
  Map<String, Object> layoutToJson() => {
        'columnWidths': List<double>.from(columnWidths),
        'rowHeights': List<double>.from(rowHeights),
        'frozenRows': _frozenRows,
        'frozenColumns': _frozenColumns,
        'filters': [
          for (final MapEntry(key: col, value: filter) in _filters.entries)
            {'column': col, ...filter.toJson()},
        ],
        'formats': [
          for (final MapEntry(key: (r, c), value: format) in _formats.entries)
            {'row': r, 'col': c, ...format.toJson()},
        ],
      };

  static List<double> _fitSizes(
    List<double>? sizes,
    int count,
    double fallback,
    double min,
  ) =>
      List<double>.generate(count, (i) {
        final size = sizes != null && i < sizes.length ? sizes[i] : fallback;
        return size.isFinite ? size.clamp(min, double.infinity) : fallback;
      }, growable: true);

  // -------------------------------------------------------------------------
  // Read-only accessors
  // -------------------------------------------------------------------------

  int get rowCount => _rows.length;

  int get colCount => _rows.isNotEmpty ? _rows[0].value.length : 0;

  ValueNotifier<List<DataCell>> rowNotifier(int row) => _rows[row];

  DataCell cellAt(int row, int col) => _rows[row].value[col];

  // -------------------------------------------------------------------------
  // Undo / Redo
  // -------------------------------------------------------------------------

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _pushSnapshot() {
    _undoStack.add(_TableSnapshot.capture(this));
    _redoStack.clear();
    if (_undoStack.length > _maxUndoDepth) _undoStack.removeAt(0);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_TableSnapshot.capture(this));
    _undoStack.removeLast().restore(this);
    _recompute();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_TableSnapshot.capture(this));
    _redoStack.removeLast().restore(this);
    _recompute();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Cell mutation
  // -------------------------------------------------------------------------

  void updateCell(int row, int col, DataCell newCell) {
    table.rows[row].cells[col] = newCell;
    final updated = List<DataCell>.from(_rows[row].value);
    updated[col] = newCell;
    _rows[row].value = updated;
    _rows[row].notifyListeners();
    _recompute();
    notifyListeners();
  }

  /// The rows of [range] the filters leave visible, clamped to the sheet.
  List<int> _visibleIn(CellRange range) => [
        for (var r = max(range.top, 0);
            r <= min(range.bottom, rowCount - 1);
            r++)
          if (!isRowHidden(r)) r,
      ];

  /// The raw values inside [range], row by row, skipping hidden rows.
  List<List<String>> valuesIn(CellRange range) => [
        for (final r in _visibleIn(range))
          [
            for (var c = range.left; c <= range.right; c++)
              cellAt(r, c).value.toString(),
          ],
      ];

  /// Writes [values] into [rows], one value row per sheet row, starting at
  /// column [left], as one undo step, or as part of the caller's when
  /// [snapshot] is false. Whatever falls outside the sheet is dropped; the
  /// sheet never grows.
  void _setCells(
    List<int> rows,
    int left,
    List<List<String>> values, {
    bool snapshot = true,
  }) {
    final count = min(rows.length, values.length);
    if (count == 0 || left < 0 || left >= colCount) return;
    if (snapshot) _pushSnapshot();
    for (var i = 0; i < count; i++) {
      final r = rows[i];
      if (r < 0 || r >= rowCount) continue;
      final row = values[i];
      final updated = List<DataCell>.from(_rows[r].value);
      for (var c = left; c < min(left + row.length, colCount); c++) {
        updated[c] = DataCell(row[c - left]);
        table.rows[r].cells[c] = updated[c];
      }
      _rows[r].value = updated;
    }
    _recompute();
    notifyListeners();
  }

  /// True when [range]'s top-left cell exists.
  bool _inSheet(CellRange range) =>
      range.top >= 0 &&
      range.left >= 0 &&
      range.top < rowCount &&
      range.left < colCount;

  /// Clear every visible cell value in [range] as one undo step, and their
  /// formats too when [formats] is true. Formats stay by default, as they do
  /// when Delete empties a cell in Google Sheets.
  void clearRange(CellRange range, {bool formats = false}) {
    final rows = _visibleIn(range);
    if (rows.isEmpty || range.left < 0 || range.left >= colCount) return;
    _pushSnapshot();
    if (formats) _formats.removeWhere((k, _) => _covers(range, rows, k));
    _setCells(
      rows,
      range.left,
      List.generate(rows.length, (_) => List.filled(range.colCount, '')),
      snapshot: false,
    );
  }

  /// True when [cell] lies in [range]'s columns on one of [rows].
  static bool _covers(CellRange range, List<int> rows, (int, int) cell) =>
      range.containsCol(cell.$2) && rows.contains(cell.$1);

  /// Paste [values] into [target] as one undo step, then select what was
  /// written.
  ///
  /// The block lands at the target's top-left corner and runs down the
  /// visible rows, skipping hidden ones. When the target's visible rows and
  /// its columns are a whole number of blocks the block repeats to fill them,
  /// so a single value fills the whole target; otherwise it is pasted once at
  /// its own size, adding rows and columns if it runs past the sheet's edge.
  ///
  /// [formats], when given, is the block's formats, row for row; they land
  /// with the values and replace the formats of the cells they cover.
  void pasteValues(
    CellRange target,
    List<List<String>> values, {
    List<List<CellFormat>>? formats,
  }) {
    if (values.isEmpty || values.first.isEmpty) return;
    if (target.top < 0 || target.left < 0) return;
    final blockRows = values.length;
    final blockCols = values.first.length;
    final targetRows = _visibleIn(target).length;
    final tiles = targetRows > 0 &&
        targetRows % blockRows == 0 &&
        target.colCount % blockCols == 0;
    final rows = tiles ? targetRows : blockRows;
    final cols = tiles ? target.colCount : blockCols;
    final dest = <int>[
      for (var r = target.top; r < rowCount; r++)
        if (!isRowHidden(r)) r,
    ].take(rows).toList();
    final start = max(rowCount, target.top);
    final missing = rows - dest.length;
    _pushSnapshot();
    _growTo(start + missing, target.left + cols);
    dest.addAll([for (var i = 0; i < missing; i++) start + i]);
    if (formats != null && formats.isNotEmpty) {
      for (var r = 0; r < rows; r++) {
        final row = formats[r % formats.length];
        for (var c = 0; c < cols; c++) {
          final i = c % blockCols;
          _setFormat(
            dest[r],
            target.left + c,
            i < row.length ? row[i] : CellFormat.plain,
          );
        }
      }
    }
    _setCells(
      dest,
      target.left,
      List.generate(
        rows,
        (r) => List.generate(cols, (c) {
          final row = values[r % blockRows];
          final i = c % blockCols;
          return i < row.length ? row[i] : '';
        }),
      ),
      snapshot: false,
    );
    selection.selectRange(
      target.top,
      target.left,
      dest.last,
      target.left + cols - 1,
    );
  }

  /// Clear the value of a single cell.
  void clearCell(int row, int col) =>
      clearRange(CellRange(top: row, left: col, bottom: row, right: col));

  /// Clear all cell values in [count] rows starting at [rowIndex].
  void clearRow(int rowIndex, {int count = 1}) {
    if (colCount == 0) return;
    clearRange(
      CellRange(
        top: rowIndex,
        left: 0,
        bottom: rowIndex + count - 1,
        right: colCount - 1,
      ),
    );
  }

  /// Clear all cell values in [count] columns starting at [colIndex].
  void clearColumn(int colIndex, {int count = 1}) {
    if (rowCount == 0) return;
    clearRange(
      CellRange(
        top: 0,
        left: colIndex,
        bottom: rowCount - 1,
        right: colIndex + count - 1,
      ),
    );
  }

  /// After rows or columns are removed, collapse the selection to one cell
  /// that still exists, so nothing reads past the sheet's new edge.
  void _collapseSelectionTo(int row, int col) {
    if (!selection.hasHighlight) return;
    if (rowCount == 0 || colCount == 0) {
      selection.clear();
    } else {
      selection.setHighlighted(min(row, rowCount - 1), min(col, colCount - 1));
    }
  }

  // -------------------------------------------------------------------------
  // Row operations
  // -------------------------------------------------------------------------

  /// Append an empty row at the end.
  void addRow() {
    _pushSnapshot();
    final cols = colCount > 0 ? colCount : 1;
    final cells = List<DataCell>.generate(cols, (_) => DataCell(''));
    table.rows.add(DataRow(List<DataCell>.from(cells)));
    _rows.add(ValueNotifier<List<DataCell>>(List<DataCell>.from(cells)));
    rowHeights.add(kDefaultRowHeight);
    _recompute();
    notifyListeners();
  }

  /// Insert an empty row at [index] (0-based). Appends if [index] >= rowCount.
  void insertRowAt(int index, {List<DataCell>? cells}) {
    _pushSnapshot();
    final cols = colCount > 0 ? colCount : 1;
    final newCells =
        cells ?? List<DataCell>.generate(cols, (_) => DataCell(''));
    final clamped = index.clamp(0, _rows.length);
    table.rows.insert(clamped, DataRow(List<DataCell>.from(newCells)));
    _rows.insert(
      clamped,
      ValueNotifier<List<DataCell>>(List<DataCell>.from(newCells)),
    );
    rowHeights.insert(clamped, kDefaultRowHeight);
    if (clamped < _hidden.length) _hidden.insert(clamped, false);
    _remapFormats(row: (r) => r >= clamped ? r + 1 : r);
    if (clamped < _frozenRows) _frozenRows++;
    _recompute();
    notifyListeners();
  }

  /// Delete [count] rows starting at [index] as one undo step. Rows the
  /// filters hide inside that span are kept.
  void deleteRowAt(int index, {int count = 1}) {
    if (index < 0 || index >= rowCount) return;
    final end = min(index + count, rowCount);
    final doomed = _visibleIn(
      CellRange(top: index, left: 0, bottom: end - 1, right: 0),
    );
    if (doomed.isEmpty) return;
    _pushSnapshot();
    for (final i in doomed.reversed) {
      _removeRow(i);
    }
    _frozenRows -= max(0, min(end, _frozenRows) - index);
    _recompute();
    _collapseSelectionTo(index, selection.highlightedCol);
    notifyListeners();
  }

  /// Removes row [i] and everything kept beside it, with no undo step.
  void _removeRow(int i) {
    table.rows.removeAt(i);
    _rows[i].dispose();
    _rows.removeAt(i);
    if (i < rowHeights.length) rowHeights.removeAt(i);
    if (i < _hidden.length) _hidden.removeAt(i);
    _remapFormats(row: (r) => r == i ? null : (r > i ? r - 1 : r));
  }

  /// Duplicate the row at [index], inserting the copy immediately after.
  void duplicateRow(int index) {
    if (index < 0 || index >= rowCount) return;
    _pushSnapshot();
    final sourceCells =
        _rows[index].value.map((c) => DataCell(c.value.toString())).toList();
    table.rows.insert(index + 1, DataRow(List<DataCell>.from(sourceCells)));
    _rows.insert(
      index + 1,
      ValueNotifier<List<DataCell>>(List<DataCell>.from(sourceCells)),
    );
    final srcH =
        index < rowHeights.length ? rowHeights[index] : kDefaultRowHeight;
    rowHeights.insert(index + 1, srcH);
    if (index < _hidden.length) _hidden.insert(index + 1, false);
    _remapFormats(row: (r) => r > index ? r + 1 : r);
    for (final MapEntry(key: (r, c), value: format) in [..._formats.entries]) {
      if (r == index) _formats[(index + 1, c)] = format;
    }
    if (index < _frozenRows) _frozenRows++;
    _recompute();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Column operations
  // -------------------------------------------------------------------------

  /// Append an empty column to every row.
  void addColumn() {
    _pushSnapshot();
    if (_rows.isEmpty) {
      table.rows.add(DataRow([DataCell('')]));
      _rows.add(ValueNotifier<List<DataCell>>([DataCell('')]));
      columnWidths.add(kDefaultColumnWidth);
      rowHeights.add(kDefaultRowHeight);
      _recompute();
      notifyListeners();
      return;
    }
    for (var i = 0; i < _rows.length; i++) {
      table.rows[i].cells.add(DataCell(''));
      final updated = List<DataCell>.from(_rows[i].value)..add(DataCell(''));
      _rows[i].value = updated;
    }
    columnWidths.add(kDefaultColumnWidth);
    _recompute();
    notifyListeners();
  }

  /// Insert an empty column at [index]. Appends if [index] >= colCount.
  void insertColumnAt(int index, {String defaultValue = ''}) {
    if (_rows.isEmpty) return;
    _pushSnapshot();
    final clamped = index.clamp(0, colCount);
    for (var i = 0; i < _rows.length; i++) {
      final newCell = DataCell(defaultValue);
      table.rows[i].cells.insert(clamped, newCell);
      final updated = List<DataCell>.from(_rows[i].value)
        ..insert(clamped, DataCell(defaultValue));
      _rows[i].value = updated;
    }
    if (clamped < columnWidths.length) {
      columnWidths.insert(clamped, kDefaultColumnWidth);
    } else {
      columnWidths.add(kDefaultColumnWidth);
    }
    if (clamped < _frozenColumns) _frozenColumns++;
    _shiftFilters(clamped, 1);
    _remapFormats(col: (c) => c >= clamped ? c + 1 : c);
    _recompute();
    notifyListeners();
  }

  /// Delete [count] columns starting at [index] as one undo step.
  void deleteColumnAt(int index, {int count = 1}) {
    if (index < 0 || index >= colCount) return;
    _pushSnapshot();
    final end = min(index + count, colCount);
    for (var i = 0; i < _rows.length; i++) {
      table.rows[i].cells.removeRange(index, end);
      _rows[i].value = List<DataCell>.from(_rows[i].value)
        ..removeRange(index, end);
    }
    if (index < columnWidths.length) {
      columnWidths.removeRange(index, min(end, columnWidths.length));
    }
    _frozenColumns -= max(0, min(end, _frozenColumns) - index);
    final hadFilters = _filters.length;
    _filters.removeWhere((col, _) => col >= index && col < end);
    _shiftFilters(end, index - end);
    _remapFormats(
      col: (c) => c < index ? c : (c >= end ? c - (end - index) : null),
    );
    _recompute();
    if (_filters.length != hadFilters) _applyFilters();
    _collapseSelectionTo(selection.highlightedRow, index);
    notifyListeners();
  }

  /// Duplicate the column at [index], inserting the copy immediately after.
  void duplicateColumn(int index) {
    if (index < 0 || index >= colCount) return;
    _pushSnapshot();
    for (var i = 0; i < _rows.length; i++) {
      final newCell = DataCell(_rows[i].value[index].value.toString());
      table.rows[i].cells.insert(index + 1, newCell);
      final updated = List<DataCell>.from(_rows[i].value)
        ..insert(index + 1, DataCell(_rows[i].value[index].value.toString()));
      _rows[i].value = updated;
    }
    final srcWidth =
        index < columnWidths.length ? columnWidths[index] : kDefaultColumnWidth;
    if (index < columnWidths.length) {
      columnWidths.insert(index + 1, srcWidth);
    } else {
      columnWidths.add(srcWidth);
    }
    if (index < _frozenColumns) _frozenColumns++;
    _shiftFilters(index + 1, 1);
    _remapFormats(col: (c) => c > index ? c + 1 : c);
    for (final MapEntry(key: (r, c), value: format) in [..._formats.entries]) {
      if (c == index) _formats[(r, index + 1)] = format;
    }
    _recompute();
    notifyListeners();
  }

  /// Moves every filter on column [from] or later by [by] columns.
  void _shiftFilters(int from, int by) {
    _filters = {
      for (final MapEntry(key: col, value: filter) in _filters.entries)
        col >= from ? col + by : col: filter,
    };
  }

  // -------------------------------------------------------------------------
  // Column width configuration
  // -------------------------------------------------------------------------

  /// Marks the start of a drag resize, so the whole drag undoes as one step.
  ///
  /// [setColumnWidth] and [setRowHeight] do not record undo history
  /// themselves, since a drag calls them once a frame.
  void beginResize() => _pushSnapshot();

  void setColumnWidths(List<double> widths) {
    columnWidths = List<double>.from(widths, growable: true);
    notifyListeners();
  }

  void setColumnWidth(int index, double width) {
    if (index < 0 || index >= columnWidths.length) return;
    columnWidths[index] = width.clamp(kMinColumnWidth, double.infinity);
    notifyListeners();
  }

  /// Auto-size column [col] to tightly fit the longest cell value.
  void autoSizeColumn(int col, {TextStyle? textStyle}) {
    if (col < 0 || col >= colCount) return;
    _pushSnapshot();
    // Horizontal overhead per side: 1px border + 1px container padding +
    // 8px TextField contentPadding = 10px → 20px total.
    // An extra 4px safety margin handles subpixel rendering variance.
    const horizontalOverhead = 24.0;
    final style = textStyle ?? const TextStyle(fontSize: 14.0);
    var maxW = kMinColumnWidth;
    for (var r = 0; r < rowCount; r++) {
      final text = formattedValueAt(r, col);
      if (text.isEmpty) continue;
      final format = formatAt(r, col);
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(
            fontWeight: format.bold ? FontWeight.bold : null,
            fontStyle: format.italic ? FontStyle.italic : null,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final w = tp.width + horizontalOverhead;
      if (w > maxW) maxW = w;
    }
    if (col < columnWidths.length) columnWidths[col] = maxW;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Row height configuration
  // -------------------------------------------------------------------------

  void setRowHeights(List<double> heights) {
    rowHeights = List<double>.from(heights, growable: true);
    notifyListeners();
  }

  void setRowHeight(int index, double height) {
    if (index < 0 || index >= rowHeights.length) return;
    rowHeights[index] = height.clamp(kMinRowHeight, double.infinity);
    notifyListeners();
  }

  /// Auto-size row [row] to fit the tallest wrapped cell content given the
  /// current column widths.
  void autoSizeRow(int row, {TextStyle? textStyle}) {
    if (row < 0 || row >= rowCount) return;
    _pushSnapshot();
    // Horizontal overhead: same as autoSizeColumn (20px) — used to constrain
    // text wrapping to the actual available width inside the cell.
    const horizontalOverhead = 20.0;
    // Vertical overhead: 1px border + 1px container padding each side = 4px.
    // An extra 2px safety margin handles subpixel rendering variance.
    const verticalOverhead = 6.0;
    final style = textStyle ?? const TextStyle(fontSize: 14.0);
    var maxH = kMinRowHeight;
    for (var c = 0; c < colCount; c++) {
      final text = _rows[row].value[c].value.toString();
      if (text.isEmpty) continue;
      final colW =
          (c < columnWidths.length ? columnWidths[c] : kDefaultColumnWidth) -
              horizontalOverhead;
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: colW.clamp(1.0, double.infinity));
      final h = tp.height + verticalOverhead;
      if (h > maxH) maxH = h;
    }
    if (row < rowHeights.length) rowHeights[row] = maxH;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Frozen panes
  // -------------------------------------------------------------------------

  /// Freezes the top [count] rows, clamped to the sheet; 0 unfreezes them.
  void setFrozenRows(int count) {
    final clamped = count.clamp(0, rowCount);
    if (clamped == _frozenRows) return;
    _pushSnapshot();
    _frozenRows = clamped;
    if (_filters.isNotEmpty) _applyFilters();
    notifyListeners();
  }

  /// Freezes the leftmost [count] columns, clamped to the sheet; 0 unfreezes
  /// them.
  void setFrozenColumns(int count) {
    final clamped = count.clamp(0, colCount);
    if (clamped == _frozenColumns) return;
    _pushSnapshot();
    _frozenColumns = clamped;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Filters
  // -------------------------------------------------------------------------

  /// The active filter on each filtered column, by column index.
  Map<int, ColumnFilter> get filters => Map.unmodifiable(_filters);

  /// Column [col]'s filter, or null when it has none.
  ColumnFilter? filterFor(int col) => _filters[col];

  /// True when any column is filtered.
  bool get hasFilters => _filters.isNotEmpty;

  /// The indexes of the rows the filters leave visible, top to bottom. Frozen
  /// rows are always among them.
  List<int> get visibleRows => _visibleRows ??= List.unmodifiable([
        for (var r = 0; r < rowCount; r++)
          if (!isRowHidden(r)) r,
      ]);

  /// True when the filters hide row [row].
  bool isRowHidden(int row) => row >= 0 && row < _hidden.length && _hidden[row];

  /// The first visible row after [from] stepping by [step] (1 down, -1 up),
  /// or [from] itself when there is none.
  int nextVisibleRow(int from, int step) {
    for (var r = from + step; r >= 0 && r < rowCount; r += step) {
      if (!isRowHidden(r)) return r;
    }
    return from;
  }

  /// The distinct values column [col] displays below the frozen rows, as a
  /// filter checklist lists them: numbers in order, then text ignoring case,
  /// then `''` for blanks when there are any.
  List<String> filterValuesFor(int col) {
    if (col < 0 || col >= colCount) return const [];
    final values = {
      for (var r = _frozenRows; r < rowCount; r++)
        ColumnFilter.valueOf(displayValueAt(r, col)),
    };
    final blank = values.remove('');
    return [...values.toList()..sort(_compareValues), if (blank) ''];
  }

  static int _compareValues(String a, String b) {
    final x = num.tryParse(a.trim());
    final y = num.tryParse(b.trim());
    if (x != null && y != null) return x.compareTo(y);
    if (x != null) return -1;
    if (y != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// Filters column [col] by [filter] and re-applies every filter, as one
  /// undo step. A null or inactive filter removes the column's filter.
  void setColumnFilter(int col, ColumnFilter? filter) {
    if (col < 0 || col >= colCount) return;
    final next = filter != null && filter.isActive ? filter : null;
    if (_filters[col] == next) return;
    _pushSnapshot();
    if (next != null) {
      _filters[col] = next;
    } else {
      _filters.remove(col);
    }
    _applyFilters();
    notifyListeners();
  }

  /// Removes every column filter, showing all rows, as one undo step.
  void clearFilters() {
    if (_filters.isEmpty) return;
    _pushSnapshot();
    _filters.clear();
    _applyFilters();
    notifyListeners();
  }

  /// Decides afresh which rows the filters hide. A selection anchored on a
  /// row that becomes hidden is cleared.
  void _applyFilters() {
    _hidden = [
      for (var r = 0; r < rowCount; r++)
        r >= _frozenRows &&
            _filters.entries.any(
              (f) => !f.value.accepts(displayValueAt(r, f.key)),
            ),
    ];
    _visibleRows = null;
    final sel = selection;
    if (isRowHidden(sel.highlightedRow) || isRowHidden(sel.activeRow)) {
      sel.clear();
    }
  }

  // -------------------------------------------------------------------------
  // Fill operations
  // -------------------------------------------------------------------------

  /// Copy the value of cell `(fromRow, col)` to all rows below it in the same
  /// column.
  void fillDown(int fromRow, int col) => fillDownRange(
        CellRange(top: fromRow, left: col, bottom: fromRow, right: col),
      );

  /// Copy the value of cell `(row, fromCol)` to all columns to the right of it
  /// in the same row.
  void fillRight(int row, int fromCol) => fillRightRange(
        CellRange(top: row, left: fromCol, bottom: row, right: fromCol),
      );

  /// Copy [range]'s top visible row down through the rest of the range's
  /// visible rows, as one undo step. A range one row tall fills its columns
  /// to the bottom of the sheet.
  void fillDownRange(CellRange range) {
    if (!_inSheet(range)) return;
    final rows = _visibleIn(
      CellRange(
        top: range.top,
        left: range.left,
        bottom: range.rowCount == 1 ? rowCount - 1 : range.bottom,
        right: range.right,
      ),
    );
    if (rows.isEmpty) return;
    final source = [
      for (var c = range.left; c <= min(range.right, colCount - 1); c++)
        cellAt(rows.first, c).value.toString(),
    ];
    _setCells(
      rows.sublist(1),
      range.left,
      List.generate(rows.length - 1, (_) => source),
    );
  }

  /// Copy [range]'s left column right through the rest of the range, in each
  /// visible row, as one undo step. A range one column wide fills its rows to
  /// the sheet's right edge.
  void fillRightRange(CellRange range) {
    if (!_inSheet(range)) return;
    final last = range.colCount == 1 ? colCount - 1 : range.right;
    final rows = _visibleIn(range);
    _setCells(rows, range.left + 1, [
      for (final r in rows)
        List.filled(last - range.left, cellAt(r, range.left).value.toString()),
    ]);
  }

  // -------------------------------------------------------------------------
  // TSV: the clipboard format Google Sheets and Excel share
  // -------------------------------------------------------------------------

  /// [range], or the selected range when omitted, as tab-separated text.
  ///
  /// Cells keep their raw text, so formulas copy as formulas. A value holding
  /// a tab, newline or double quote is wrapped in quotes with its quotes
  /// doubled, which is what Google Sheets and Excel write and read. Returns an
  /// empty string when there is no range.
  String rangeToTsv([CellRange? range]) {
    range ??= selection.range;
    if (range == null ||
        !_inSheet(range) ||
        range.bottom >= rowCount ||
        range.right >= colCount) {
      return '';
    }
    return valuesIn(
      range,
    ).map((row) => row.map(_tsvField).join('\t')).join('\n');
  }

  /// [rangeToTsv], remembering the formats of the cells it copied so that
  /// [pasteTsv] carries them when the same text is pasted back into this
  /// sheet. Text from anywhere else pastes values only.
  String copyRange([CellRange? range]) {
    range ??= selection.range;
    final tsv = rangeToTsv(range);
    _copied = tsv.isEmpty
        ? null
        : (
            tsv: tsv,
            formats: [
              for (final r in _visibleIn(range!))
                [
                  for (var c = range.left; c <= range.right; c++)
                    formatAt(r, c),
                ],
            ],
          );
    return tsv;
  }

  static String _tsvField(String v) =>
      v.contains(RegExp('[\t\n\r"]')) ? '"${v.replaceAll('"', '""')}"' : v;

  /// Parses tab-separated text, as Google Sheets and Excel put it on the
  /// clipboard, into rows of equal length.
  ///
  /// A field that starts with a double quote is quoted: it runs to the next
  /// lone quote and may hold tabs and newlines, and `""` inside it is one
  /// quote. A quote anywhere else is literal. LF and CRLF both end a row, one
  /// trailing line ending is dropped, and short rows are padded with empty
  /// strings.
  static List<List<String>> parseTsv(String tsv) {
    final rows = <List<String>>[];
    var fields = <String>[];
    final field = StringBuffer();
    var i = 0;
    final n = tsv.length;
    var atFieldStart = true;
    while (i < n) {
      final ch = tsv[i];
      if (atFieldStart && ch == '"') {
        i++;
        while (i < n) {
          if (tsv[i] == '"') {
            if (i + 1 < n && tsv[i + 1] == '"') {
              field.write('"');
              i += 2;
              continue;
            }
            i++;
            break;
          }
          field.write(tsv[i++]);
        }
        atFieldStart = false;
      } else if (ch == '\t') {
        fields.add(field.toString());
        field.clear();
        atFieldStart = true;
        i++;
      } else if (ch == '\n' ||
          (ch == '\r' && i + 1 < n && tsv[i + 1] == '\n')) {
        fields.add(field.toString());
        field.clear();
        rows.add(fields);
        fields = [];
        atFieldStart = true;
        i += ch == '\r' ? 2 : 1;
      } else {
        field.write(ch);
        atFieldStart = false;
        i++;
      }
    }
    // Text that does not end with a line ending still has a last row.
    if (!atFieldStart || fields.isNotEmpty) {
      fields.add(field.toString());
      rows.add(fields);
    }
    final width = rows.fold(0, (w, r) => r.length > w ? r.length : w);
    return [
      for (final r in rows) [...r, ...List.filled(width - r.length, '')],
    ];
  }

  /// Pastes tab-separated text into [target], or the selected range when
  /// omitted, through [pasteValues]. Text this sheet's [copyRange] produced
  /// last brings its cells' formats with it.
  void pasteTsv(String tsv, [CellRange? target]) {
    target ??= selection.range;
    final copied = _copied;
    if (target == null) return;
    pasteValues(
      target,
      parseTsv(tsv),
      formats: copied != null && copied.tsv == tsv ? copied.formats : null,
    );
  }

  /// Adds empty rows and columns until the sheet is at least [rows] by
  /// [cols]. Records no undo history.
  void _growTo(int rows, int cols) {
    final addCols = cols - colCount;
    if (addCols > 0) {
      for (var r = 0; r < rowCount; r++) {
        final extra = List.generate(addCols, (_) => DataCell(''));
        table.rows[r].cells.addAll(extra);
        _rows[r].value = [..._rows[r].value, ...extra];
      }
      columnWidths.addAll(List.filled(addCols, kDefaultColumnWidth));
    }
    final width = max(cols, colCount);
    while (rowCount < rows) {
      final cells = List.generate(width, (_) => DataCell(''));
      table.rows.add(DataRow(List<DataCell>.from(cells)));
      _rows.add(ValueNotifier<List<DataCell>>(cells));
      rowHeights.add(kDefaultRowHeight);
    }
  }

  // -------------------------------------------------------------------------
  // Cell formats
  // -------------------------------------------------------------------------

  /// Every formatted cell's format, by (row, col). Cells absent from it are
  /// [CellFormat.plain].
  Map<(int, int), CellFormat> get formats => Map.unmodifiable(_formats);

  /// The format of the cell at [row], [col].
  CellFormat formatAt(int row, int col) =>
      _formats[(row, col)] ?? CellFormat.plain;

  /// The text the cell at [row], [col] shows: [displayValueAt] in the cell's
  /// number format.
  String formattedValueAt(int row, int col) =>
      formatCellValue(displayValueAt(row, col), formatAt(row, col));

  /// Replaces the format of every visible cell in [range] with [change]
  /// applied to it, as one undo step. Hidden rows are skipped, as every range
  /// operation skips them. Does nothing, and records no undo step, when no
  /// format would change.
  ///
  /// ```dart
  /// controller.applyFormat(range, (f) => f.withBold(true));
  /// ```
  void applyFormat(
    CellRange range,
    CellFormat Function(CellFormat format) change,
  ) {
    final updates = <(int, int), CellFormat>{
      for (final r in _visibleIn(range))
        for (var c = max(range.left, 0);
            c <= min(range.right, colCount - 1);
            c++)
          (r, c): change(formatAt(r, c)),
    }..removeWhere((cell, format) => format == formatAt(cell.$1, cell.$2));
    if (updates.isEmpty) return;
    _pushSnapshot();
    for (final MapEntry(key: (r, c), value: format) in updates.entries) {
      _setFormat(r, c, format);
    }
    notifyListeners();
  }

  /// Removes every format from the visible cells of [range], keeping their
  /// values, as one undo step.
  void clearFormats(CellRange range) =>
      applyFormat(range, (_) => CellFormat.plain);

  /// Stores [format] for the cell, dropping the entry when it is plain.
  void _setFormat(int row, int col, CellFormat format) {
    if (format.isPlain) {
      _formats.remove((row, col));
    } else {
      _formats[(row, col)] = format;
    }
  }

  /// Moves every format to the cell [row] and [col] map its row and column
  /// to; a null drops it. Either defaults to leaving the index alone.
  void _remapFormats({
    int? Function(int) row = _same,
    int? Function(int) col = _same,
  }) {
    _formats = {
      for (final MapEntry(key: (r, c), value: format) in _formats.entries)
        if ((row(r), col(c)) case (final r2?, final c2?)) (r2, c2): format,
    };
  }

  static int? _same(int index) => index;

  // -------------------------------------------------------------------------
  // Sort / deduplication
  // -------------------------------------------------------------------------

  /// Sort all rows by the values in [col] (0-based). Numeric values are sorted
  /// numerically; anything else is sorted lexicographically.
  void sortByColumn(int col, {bool ascending = true}) {
    if (col < 0 || col >= colCount || rowCount == 0) return;
    _pushSnapshot();
    // Build index list to keep rowHeights in sync with row reordering.
    final indices = List<int>.generate(rowCount, (i) => i);
    indices.sort((a, b) {
      final av = table.rows[a].cells[col].value.toString();
      final bv = table.rows[b].cells[col].value.toString();
      final n1 = num.tryParse(av);
      final n2 = num.tryParse(bv);
      final cmp =
          (n1 != null && n2 != null) ? n1.compareTo(n2) : av.compareTo(bv);
      return ascending ? cmp : -cmp;
    });
    final sortedTableRows = indices.map((i) => table.rows[i]).toList();
    final sortedHeights = indices
        .map((i) => i < rowHeights.length ? rowHeights[i] : kDefaultRowHeight)
        .toList();
    _hidden = [for (final i in indices) isRowHidden(i)];
    final sortedTo = List<int>.filled(indices.length, 0);
    for (var i = 0; i < indices.length; i++) {
      sortedTo[indices[i]] = i;
    }
    _remapFormats(row: (r) => sortedTo[r]);
    table.rows
      ..clear()
      ..addAll(sortedTableRows);
    for (var i = 0; i < _rows.length; i++) {
      _rows[i].value = List<DataCell>.from(table.rows[i].cells);
    }
    rowHeights
      ..clear()
      ..addAll(sortedHeights);
    _recompute();
    notifyListeners();
  }

  /// Remove duplicate rows (all cell values must match). First occurrence is
  /// kept.
  void removeDuplicateRows() {
    if (rowCount == 0) return;
    _pushSnapshot();
    final seen = <String>{};
    final toRemove = <int>[];
    for (var i = 0; i < _rows.length; i++) {
      final key = _rows[i].value.map((c) => c.value.toString()).join('\x00');
      if (!seen.add(key)) toRemove.add(i);
    }
    for (final i in toRemove.reversed) {
      _removeRow(i);
      if (i < _frozenRows) _frozenRows--;
    }
    _recompute();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Find / Replace
  // -------------------------------------------------------------------------

  /// Return all `(row, col)` pairs whose cell value contains [query].
  List<({int row, int col})> findCells(
    String query, {
    bool caseSensitive = false,
  }) {
    final results = <({int row, int col})>[];
    final q = caseSensitive ? query : query.toLowerCase();
    for (var r = 0; r < _rows.length; r++) {
      for (var c = 0; c < _rows[r].value.length; c++) {
        final v = caseSensitive
            ? _rows[r].value[c].value.toString()
            : _rows[r].value[c].value.toString().toLowerCase();
        if (v.contains(q)) results.add((row: r, col: c));
      }
    }
    return results;
  }

  /// Replace all occurrences of [from] with [to] in every cell. Returns the
  /// number of cells that were changed.
  int replaceCells(String from, String to, {bool caseSensitive = false}) {
    if (from.isEmpty) return 0;
    _pushSnapshot();
    var count = 0;
    for (var r = 0; r < _rows.length; r++) {
      final updated = List<DataCell>.from(_rows[r].value);
      var rowChanged = false;
      for (var c = 0; c < updated.length; c++) {
        final v = updated[c].value.toString();
        final newV = caseSensitive
            ? v.replaceAll(from, to)
            : v.replaceAllMapped(
                RegExp(RegExp.escape(from), caseSensitive: false),
                (_) => to,
              );
        if (newV != v) {
          updated[c] = DataCell(newV);
          table.rows[r].cells[c] = DataCell(newV);
          count++;
          rowChanged = true;
        }
      }
      if (rowChanged) _rows[r].value = updated;
    }
    if (count > 0) {
      _recompute();
      notifyListeners();
    }
    return count;
  }

  // -------------------------------------------------------------------------
  // CSV export / import
  // -------------------------------------------------------------------------

  /// Return the table as a RFC-4180-compliant CSV string.
  String exportCsv() {
    return _rows.map((row) {
      return row.value.map((cell) {
        final v = cell.value.toString();
        if (v.contains(',') || v.contains('"') || v.contains('\n')) {
          return '"${v.replaceAll('"', '""')}"';
        }
        return v;
      }).join(',');
    }).join('\n');
  }

  /// Replace the entire table with rows parsed from [csv].
  ///
  /// Follows RFC-4180:
  /// - Fields may be enclosed in double-quotes.
  /// - A double-quote inside a quoted field is escaped as "".
  /// - Quoted fields may span multiple lines.
  /// - Both LF and CRLF are accepted as record separators.
  /// - Completely empty or whitespace-only *unquoted* lines are skipped.
  void loadFromCsv(String csv) {
    _pushSnapshot();
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    table.rows.clear();

    final parsedRows = _parseCsv(csv);
    for (final rowValues in parsedRows) {
      if (rowValues.isEmpty) continue;
      final cells = rowValues.map(DataCell.new).toList();
      table.rows.add(DataRow(List<DataCell>.from(cells)));
      _rows.add(ValueNotifier<List<DataCell>>(List<DataCell>.from(cells)));
    }
    final newColCount = _rows.isNotEmpty ? _rows[0].value.length : 0;
    columnWidths = List<double>.filled(
      newColCount,
      kDefaultColumnWidth,
      growable: true,
    );
    rowHeights = List<double>.filled(
      _rows.length,
      kDefaultRowHeight,
      growable: true,
    );
    _frozenRows = _frozenRows.clamp(0, _rows.length);
    _frozenColumns = _frozenColumns.clamp(0, newColCount);
    _filters.clear();
    _hidden = [];
    _formats = {};
    _recompute();
    notifyListeners();
  }

  /// Full RFC-4180 CSV parser.
  ///
  /// Handles:
  ///  - Quoted fields (may contain commas, newlines, escaped quotes)
  ///  - Both LF and CRLF record separators
  ///  - Trailing commas (empty last field)
  ///  - Blank / whitespace-only lines are skipped
  static List<List<String>> _parseCsv(String csv) {
    final rows = <List<String>>[];
    var fields = <String>[];
    var i = 0;
    final n = csv.length;

    while (i <= n) {
      if (i == n) {
        // End of input: flush the current row.
        // If the last character was a comma, there is an implicit trailing
        // empty field (e.g. "a,b," has three fields, the last being empty).
        if (n > 0 && csv[n - 1] == ',') fields.add('');
        // Skip only a truly empty row (no fields accumulated at all).
        if (fields.isNotEmpty) rows.add(fields);
        break;
      }

      final ch = csv[i];

      if (ch == '"') {
        // Quoted field — may contain commas and newlines.
        i++;
        final buf = StringBuffer();
        while (i < n) {
          final c = csv[i];
          if (c == '"') {
            if (i + 1 < n && csv[i + 1] == '"') {
              // Escaped double-quote.
              buf.write('"');
              i += 2;
            } else {
              // Closing quote.
              i++;
              break;
            }
          } else {
            buf.write(c);
            i++;
          }
        }
        fields.add(buf.toString());
        // Consume comma or record separator after the closing quote.
        if (i < n && csv[i] == ',') {
          i++;
        } else if (i < n && csv[i] == '\r' && i + 1 < n && csv[i + 1] == '\n') {
          rows.add(fields);
          fields = [];
          i += 2;
        } else if (i < n && csv[i] == '\n') {
          rows.add(fields);
          fields = [];
          i++;
        }
      } else if (ch == '\r' && i + 1 < n && csv[i + 1] == '\n') {
        // CRLF record separator.
        // Only add a trailing empty field if the last char before CRLF was a
        // comma (i.e. the row ended with a delimiter, meaning a trailing empty
        // field was intended).
        if (i > 0 && csv[i - 1] == ',') fields.add('');
        final row = fields;
        fields = [];
        // Skip completely blank lines: no fields, or a single field that is
        // empty (a bare newline). Whitespace-only cells are kept.
        final isBlankLine = row.isEmpty || (row.length == 1 && row[0].isEmpty);
        if (!isBlankLine) rows.add(row);
        i += 2;
      } else if (ch == '\n') {
        // LF record separator.
        if (i > 0 && csv[i - 1] == ',') fields.add('');
        final row = fields;
        fields = [];
        final isBlankLine = row.isEmpty || (row.length == 1 && row[0].isEmpty);
        if (!isBlankLine) rows.add(row);
        i++;
      } else if (ch == ',') {
        // Field separator — the current (unquoted) field ended.
        fields.add('');
        i++;
      } else {
        // Unquoted field: read up to the next comma, LF, CRLF, or EOF.
        final buf = StringBuffer();
        while (i < n &&
            csv[i] != ',' &&
            csv[i] != '\n' &&
            !(csv[i] == '\r' && i + 1 < n && csv[i + 1] == '\n')) {
          buf.write(csv[i++]);
        }
        fields.add(buf.toString());
        // If we stopped at a comma, consume it and continue.
        if (i < n && csv[i] == ',') i++;
      }
    }

    return rows;
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    selection.removeListener(_onSelectionChanged);
    selection.dispose();
    activeCellEditingController.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }
}
