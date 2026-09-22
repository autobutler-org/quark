import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier, ValueNotifier;
import 'package:flutter/material.dart' show Color;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:quark_formula/evaluation/evaluation.dart';

import '../../data_table.dart';
import 'cell/heading/heading_cells.dart'
    show kDefaultColumnWidth, kDefaultRowHeight, kMinColumnWidth, kMinRowHeight;
import 'data_sheet_selection.dart';

// ---------------------------------------------------------------------------
// Internal snapshot used for undo / redo.
// ---------------------------------------------------------------------------

class _TableSnapshot {
  final List<List<String>> cells; // [row][col] as strings
  final List<double> columnWidths;
  final List<double> rowHeights;

  _TableSnapshot(this.cells, this.columnWidths, this.rowHeights);

  factory _TableSnapshot.capture(DataSheetController c) {
    return _TableSnapshot(
      List.generate(
        c._rows.length,
        (r) => c._rows[r].value.map((cell) => cell.value.toString()).toList(),
      ),
      List<double>.from(c.columnWidths),
      List<double>.from(c.rowHeights),
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
  }
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// The state behind a `DataSheet`: the table, column widths and row heights, the evaluated value of each cell,
/// and undo and redo.
class DataSheetController extends ChangeNotifier {
  final DataTable table;
  final List<ValueNotifier<List<DataCell>>> _rows;

  /// Per-column pixel widths. Length equals [colCount].
  List<double> columnWidths;

  /// Per-row pixel heights. Length equals [rowCount].
  List<double> rowHeights;

  /// Selection state shared between the sheet view and the control bar.
  final DataSheetSelectionModel selection = DataSheetSelectionModel();

  /// Overlay of formula-evaluated values, keyed by (row, col).
  /// Only formula cells appear here; literal cells are absent.
  Map<(int, int), FormulaValue> _computedValues = {};

  /// Color assignments for cells referenced by the formula currently being
  /// edited. Set by [DataSheetFormulaBar] while a formula is active;
  /// cleared when editing commits or cancels.
  Map<(int, int), Color> activeRefColors = {};

  /// Shared [TextEditingController] for the currently active (in-edit) cell.
  /// Both the [DataSheet] cell editor and [DataSheetFormulaBar] use this
  /// single controller so they remain in sync without extra bridging logic.
  final TextEditingController activeCellEditingController =
      TextEditingController();

  final List<_TableSnapshot> _undoStack = [];
  final List<_TableSnapshot> _redoStack = [];

  static const int _maxUndoDepth = 100;

  DataSheetController._(
      this.table, this._rows, this.columnWidths, this.rowHeights) {
    selection.addListener(_onSelectionChanged);
    _recompute();
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

  /// Sets the active reference color map and notifies listeners so the grid
  /// redraws the reference borders.
  void setActiveRefColors(Map<(int, int), Color> colors) {
    activeRefColors = colors;
    notifyListeners();
  }

  /// Clears the active reference color map.
  void clearActiveRefColors() {
    if (activeRefColors.isEmpty) return;
    activeRefColors = {};
    notifyListeners();
  }

  static String _formatFormulaValue(FormulaValue v) => switch (v) {
        NumberValue(:final value) => value == value.truncateToDouble()
            ? value.toInt().toString()
            : value.toString(),
        StringValue(:final value) => value,
        BoolValue(:final value) => value ? 'TRUE' : 'FALSE',
        ErrorValue(:final code) => code,
      };

  factory DataSheetController.fromTable(
    DataTable table, {
    List<double>? columnWidths,
    List<double>? rowHeights,
    // Deprecated: kept for call-site compatibility only.
    List<int>? columnFlex,
  }) {
    final rows = table.rows
        .map((r) => ValueNotifier<List<DataCell>>(List<DataCell>.from(r.cells)))
        .toList();
    final colCount = table.rows.isNotEmpty ? table.rows.first.cells.length : 0;
    final rowCount = table.rows.length;
    final widths = columnWidths != null
        ? List<double>.from(columnWidths, growable: true)
        : List<double>.filled(colCount, kDefaultColumnWidth, growable: true);
    final heights = rowHeights != null
        ? List<double>.from(rowHeights, growable: true)
        : List<double>.filled(rowCount, kDefaultRowHeight, growable: true);
    return DataSheetController._(table, rows, widths, heights);
  }

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

  /// Clear the value of a single cell.
  void clearCell(int row, int col) {
    if (row < 0 || row >= rowCount || col < 0 || col >= colCount) return;
    _pushSnapshot();
    updateCell(row, col, DataCell(''));
  }

  /// Clear all cell values in [rowIndex].
  void clearRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= rowCount) return;
    _pushSnapshot();
    final empty = List<DataCell>.generate(colCount, (_) => DataCell(''));
    for (var c = 0; c < colCount; c++) {
      table.rows[rowIndex].cells[c] = empty[c];
    }
    _rows[rowIndex].value = empty;
    _recompute();
    notifyListeners();
  }

  /// Clear all cell values in [colIndex].
  void clearColumn(int colIndex) {
    if (colIndex < 0 || colIndex >= colCount) return;
    _pushSnapshot();
    for (var r = 0; r < rowCount; r++) {
      table.rows[r].cells[colIndex] = DataCell('');
      final updated = List<DataCell>.from(_rows[r].value);
      updated[colIndex] = DataCell('');
      _rows[r].value = updated;
    }
    _recompute();
    notifyListeners();
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
        clamped, ValueNotifier<List<DataCell>>(List<DataCell>.from(newCells)));
    rowHeights.insert(clamped, kDefaultRowHeight);
    _recompute();
    notifyListeners();
  }

  /// Delete the row at [index].
  void deleteRowAt(int index) {
    if (index < 0 || index >= rowCount) return;
    _pushSnapshot();
    table.rows.removeAt(index);
    _rows[index].dispose();
    _rows.removeAt(index);
    if (index < rowHeights.length) rowHeights.removeAt(index);
    _recompute();
    notifyListeners();
  }

  /// Duplicate the row at [index], inserting the copy immediately after.
  void duplicateRow(int index) {
    if (index < 0 || index >= rowCount) return;
    _pushSnapshot();
    final sourceCells =
        _rows[index].value.map((c) => DataCell(c.value.toString())).toList();
    table.rows.insert(index + 1, DataRow(List<DataCell>.from(sourceCells)));
    _rows.insert(index + 1,
        ValueNotifier<List<DataCell>>(List<DataCell>.from(sourceCells)));
    final srcH =
        index < rowHeights.length ? rowHeights[index] : kDefaultRowHeight;
    rowHeights.insert(index + 1, srcH);
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
    _recompute();
    notifyListeners();
  }

  /// Delete the column at [index].
  void deleteColumnAt(int index) {
    if (index < 0 || index >= colCount) return;
    _pushSnapshot();
    for (var i = 0; i < _rows.length; i++) {
      table.rows[i].cells.removeAt(index);
      final updated = List<DataCell>.from(_rows[i].value)..removeAt(index);
      _rows[i].value = updated;
    }
    if (index < columnWidths.length) columnWidths.removeAt(index);
    _recompute();
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
    _recompute();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Column width configuration
  // -------------------------------------------------------------------------

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
    // Horizontal overhead per side: 1px border + 1px container padding +
    // 8px TextField contentPadding = 10px → 20px total.
    // An extra 4px safety margin handles subpixel rendering variance.
    const horizontalOverhead = 24.0;
    final style = textStyle ?? const TextStyle(fontSize: 14.0);
    var maxW = kMinColumnWidth;
    for (var r = 0; r < rowCount; r++) {
      final text = _rows[r].value[col].value.toString();
      if (text.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
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
  // Fill operations
  // -------------------------------------------------------------------------

  /// Copy the value of cell `(fromRow, col)` to all rows below it in the same
  /// column.
  void fillDown(int fromRow, int col) {
    if (fromRow < 0 || fromRow >= rowCount || col < 0 || col >= colCount) {
      return;
    }
    if (fromRow == rowCount - 1) return;
    _pushSnapshot();
    final sourceValue = _rows[fromRow].value[col].value.toString();
    for (var r = fromRow + 1; r < rowCount; r++) {
      table.rows[r].cells[col] = DataCell(sourceValue);
      final updated = List<DataCell>.from(_rows[r].value);
      updated[col] = DataCell(sourceValue);
      _rows[r].value = updated;
    }
    _recompute();
    notifyListeners();
  }

  /// Copy the value of cell `(row, fromCol)` to all columns to the right of it
  /// in the same row.
  void fillRight(int row, int fromCol) {
    if (row < 0 || row >= rowCount || fromCol < 0 || fromCol >= colCount) {
      return;
    }
    if (fromCol == colCount - 1) return;
    _pushSnapshot();
    final sourceValue = _rows[row].value[fromCol].value.toString();
    final updated = List<DataCell>.from(_rows[row].value);
    for (var c = fromCol + 1; c < colCount; c++) {
      table.rows[row].cells[c] = DataCell(sourceValue);
      updated[c] = DataCell(sourceValue);
    }
    _rows[row].value = updated;
    _recompute();
    notifyListeners();
  }

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
      table.rows.removeAt(i);
      _rows[i].dispose();
      _rows.removeAt(i);
      if (i < rowHeights.length) rowHeights.removeAt(i);
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
    columnWidths =
        List<double>.filled(newColCount, kDefaultColumnWidth, growable: true);
    rowHeights =
        List<double>.filled(_rows.length, kDefaultRowHeight, growable: true);
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
