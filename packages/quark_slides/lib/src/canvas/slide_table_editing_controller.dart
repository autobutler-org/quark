import 'package:flutter/foundation.dart';

import '../controller/slide_document_controller.dart';
import '../geometry/slide_tree.dart';
import '../model/cell_format.dart';
import '../model/cell_range.dart';
import '../model/slide_color.dart';
import '../model/slide_element.dart';
import '../model/text_paragraph.dart';

/// The cells selected in a table on an editing `SlideCanvas`, and the table
/// commands a toolbar sends to them.
///
/// Give one to `SlideCanvas.tableEditing` and to the toolbar, and keep it
/// for the canvas's life (the canvas makes its own when none is given). The
/// canvas selects cells as the user taps, drags and arrows through a
/// selected table, and clears them when the table is no longer selected;
/// the toolbar listens to show its table controls and calls the commands,
/// each **one undo step** on the document, on the selected cells:
///
/// ```dart
/// final tables = SlideTableEditingController();
/// SlideCanvas(document: doc, slideId: slideId, tableEditing: tables, ...);
///
/// ListenableBuilder(
///   listenable: tables,
///   builder: (context, _) => Row(children: [
///     IconButton(
///       onPressed: tables.hasSelection ? tables.insertRowBelow : null,
///       icon: const Icon(Icons.table_rows),
///     ),
///     IconButton(
///       onPressed: tables.canMerge ? tables.merge : null,
///       icon: const Icon(Icons.call_merge),
///     ),
///   ]),
/// );
/// tables.format(const CellFormat(text: TextFormat(bold: true)));
/// tables.format(const CellFormat(borders: CellBorderPreset.outside));
/// ```
///
/// After a row or column is inserted or deleted the selection moves with
/// the cells it was on. A selection the document no longer has room for —
/// after an undo, say — reads as none.
class SlideTableEditingController extends ChangeNotifier {
  SlideDocumentController? _doc;
  String? _slideId;
  String? _tableId;
  CellRange? _range;
  ({int row, int column})? _active;

  /// Points the controller at the slide [slideId] of [document].
  /// `SlideCanvas` calls this as it builds; an app does not need to.
  void attach(SlideDocumentController document, String slideId) {
    if (_doc != document || _slideId != slideId) {
      _tableId = null;
      _range = null;
      _active = null;
    }
    _doc = document;
    _slideId = slideId;
  }

  /// The table whose cells are selected, as the document has it now, or
  /// `null`.
  TableElement? get table {
    final id = _tableId;
    final element = id == null
        ? null
        : _doc?.presentation.slideById(_slideId ?? '')?.findElement(id);
    return element is TableElement ? element : null;
  }

  /// The id of the table whose cells are selected, or `null`.
  String? get tableId => range == null ? null : _tableId;

  /// The selected cells, or `null` when none are (or the table has
  /// changed so that they no longer fit).
  CellRange? get range {
    final range = _range;
    final table = this.table;
    if (range == null || table == null) return null;
    if (range.bottom >= table.rowCount || range.right >= table.columnCount) {
      return null;
    }
    return range;
  }

  /// The cell the keyboard is on: where the selection started, which
  /// Enter edits and the arrows move from. `null` with no selection.
  ({int row, int column})? get active {
    final range = this.range;
    final active = _active;
    if (range == null || active == null) return null;
    return range.contains(active.row, active.column)
        ? active
        : (row: range.top, column: range.left);
  }

  /// Whether any cells are selected.
  bool get hasSelection => range != null;

  /// Whether [merge] would merge anything: more than one cell is selected.
  bool get canMerge {
    final table = this.table;
    final range = this.range;
    return table != null &&
        range != null &&
        !table.expandToMerges(range).isSingle;
  }

  /// Whether [unmerge] would split anything: a merged cell is selected.
  bool get canUnmerge {
    final table = this.table;
    final range = this.range;
    if (table == null || range == null) return false;
    final area = table.expandToMerges(range);
    for (var r = area.top; r <= area.bottom; r++) {
      for (var c = area.left; c <= area.right; c++) {
        if (table.cell(r, c).isMerged) return true;
      }
    }
    return false;
  }

  /// Selects [range] of the table [tableId], grown to take in any merge it
  /// cuts through, with [active] (its first cell by default) as the cell
  /// the keyboard is on.
  void select(
    String tableId,
    CellRange range, {
    ({int row, int column})? active,
  }) {
    _tableId = tableId;
    final table = this.table;
    final next = table == null ? range : table.expandToMerges(range);
    final focus = active ?? (row: range.top, column: range.left);
    if (next == _range && focus == _active) return;
    _range = next;
    _active = focus;
    notifyListeners();
  }

  /// Selects no cells.
  void clear() {
    if (_range == null && _tableId == null) return;
    _tableId = null;
    _range = null;
    _active = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  /// Inserts a row above the selection.
  void insertRowAbove() => _onSelection((doc, slide, id, range) {
        doc.insertTableRow(slide, id, range.top);
        _shift(rows: 1);
      });

  /// Inserts a row below the selection.
  void insertRowBelow() => _onSelection(
        (doc, slide, id, range) =>
            doc.insertTableRow(slide, id, range.bottom, after: true),
      );

  /// Inserts a column left of the selection.
  void insertColumnLeft() => _onSelection((doc, slide, id, range) {
        doc.insertTableColumn(slide, id, range.left);
        _shift(columns: 1);
      });

  /// Inserts a column right of the selection.
  void insertColumnRight() => _onSelection(
        (doc, slide, id, range) =>
            doc.insertTableColumn(slide, id, range.right, after: true),
      );

  /// Deletes the selected rows; deleting them all deletes the table.
  void deleteRows() => _onSelection((doc, slide, id, range) {
        doc.deleteTableRow(slide, id, range.top, count: range.rowCount);
        _collapse();
      });

  /// Deletes the selected columns; deleting them all deletes the table.
  void deleteColumns() => _onSelection((doc, slide, id, range) {
        doc.deleteTableColumn(slide, id, range.left, count: range.columnCount);
        _collapse();
      });

  /// Applies [format] to the selected cells. See [CellFormat].
  void format(CellFormat format) => _onSelection(
        (doc, slide, id, range) => doc.formatCells(slide, id, range, format),
      );

  /// Merges the selected cells into one.
  void merge() => _onSelection((doc, slide, id, range) {
        doc.mergeCells(slide, id, range);
        select(id, range);
      });

  /// Splits every merged cell in the selection back into its cells.
  void unmerge() => _onSelection(
        (doc, slide, id, range) => doc.unmergeCells(slide, id, range),
      );

  /// Empties the text of the selected cells, as the Delete key does.
  void clearText() => _onSelection((doc, slide, id, range) {
        doc.batch(() {
          final table = this.table!;
          for (var r = range.top; r <= range.bottom; r++) {
            for (var c = range.left; c <= range.right; c++) {
              if (table.isCovered(r, c) || table.cell(r, c).plainText.isEmpty) {
                continue;
              }
              doc.setCellText(slide, id, r, c, const [TextParagraph([])]);
            }
          }
        });
      });

  /// Turns the table's header row and banded rows on or off and sets its
  /// header [accent]; what is left out is kept.
  void setStyle({bool? headerRow, bool? bandedRows, SlideColor? accent}) =>
      _onSelection(
        (doc, slide, id, range) => doc.setTableStyle(
          slide,
          id,
          headerRow: headerRow,
          bandedRows: bandedRows,
          accent: accent,
        ),
      );

  /// Runs [command] on the selection, when there is one, and notifies.
  void _onSelection(
    void Function(
      SlideDocumentController doc,
      String slideId,
      String tableId,
      CellRange range,
    ) command,
  ) {
    final doc = _doc;
    final range = this.range;
    final id = _tableId;
    if (doc == null || range == null || id == null) return;
    command(doc, _slideId!, id, range);
    notifyListeners();
  }

  void _shift({int rows = 0, int columns = 0}) {
    final range = _range!;
    _range = CellRange(
      top: range.top + rows,
      left: range.left + columns,
      bottom: range.bottom + rows,
      right: range.right + columns,
    );
    final active = _active;
    if (active != null) {
      _active = (row: active.row + rows, column: active.column + columns);
    }
  }

  /// After a delete: the first cell left at or before where the selection
  /// began, or none when the table went.
  void _collapse() {
    final table = this.table;
    final range = _range!;
    if (table == null) {
      _tableId = null;
      _range = null;
      _active = null;
      return;
    }
    final row = range.top.clamp(0, table.rowCount - 1);
    final column = range.left.clamp(0, table.columnCount - 1);
    _range = table.expandToMerges(CellRange.single(row, column));
    _active = (row: row, column: column);
  }
}
