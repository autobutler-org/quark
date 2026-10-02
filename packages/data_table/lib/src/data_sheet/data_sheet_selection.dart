import 'package:flutter/foundation.dart';

import 'cell_range.dart';

/// Tracks the active editing cell, the highlighted navigation cell, and the
/// rectangular range around it for a [DataSheetController].
///
/// The highlighted cell is the range's anchor: it is the cell that keeps the
/// strong outline, the one typing edits, and the one single-cell operations
/// act on. The *extent* is the opposite corner, moved by Shift+arrows,
/// Shift+click, and drag. With no extent set the range is just the
/// highlighted cell, so callers that never extend see single-cell behavior.
///
/// The controller embeds one of these and propagates its change notifications
/// through its own [notifyListeners], so any widget that listens to the
/// controller automatically reacts to selection changes too.
class DataSheetSelectionModel extends ChangeNotifier {
  int _activeRow = -1;
  int _activeCol = -1;
  int _highlightedRow = -1;
  int _highlightedCol = -1;
  int _extentRow = -1;
  int _extentCol = -1;

  int get activeRow => _activeRow;
  int get activeCol => _activeCol;
  int get highlightedRow => _highlightedRow;
  int get highlightedCol => _highlightedCol;

  /// Row of the range corner opposite the highlighted cell; the highlighted
  /// row when the range is a single cell, and -1 when nothing is highlighted.
  int get extentRow => _extentRow >= 0 ? _extentRow : _highlightedRow;

  /// Column of the range corner opposite the highlighted cell.
  int get extentCol => _extentCol >= 0 ? _extentCol : _highlightedCol;

  /// True when a cell is in edit mode.
  bool get hasActiveCell => _activeRow >= 0;

  /// True when a cell is highlighted (keyboard-navigated but not editing).
  bool get hasHighlight => _highlightedRow >= 0;

  /// The selected rectangle, or `null` when nothing is highlighted.
  CellRange? get range {
    if (!hasHighlight) return null;
    return CellRange.fromCorners(
      _highlightedRow,
      _highlightedCol,
      extentRow,
      extentCol,
    );
  }

  /// True when the selection spans more than one cell.
  bool get hasRange => !(range?.isSingleCell ?? true);

  /// True when ([row], [col]) is inside the selected range.
  bool isInRange(int row, int col) => range?.contains(row, col) ?? false;

  /// The row that context-sensitive operations (delete, sort, fill, …) should
  /// act on: the highlighted row if set, otherwise the active editing row.
  int get contextRow => _highlightedRow >= 0 ? _highlightedRow : _activeRow;

  /// The column that context-sensitive operations should act on.
  int get contextCol => _highlightedCol >= 0 ? _highlightedCol : _activeCol;

  /// The cells context-sensitive operations act on: the selected range, or
  /// the cell being edited when nothing is highlighted.
  CellRange? get contextRange =>
      range ??
      (hasActiveCell
          ? CellRange.fromCorners(
              _activeRow, _activeCol, _activeRow, _activeCol)
          : null);

  /// Mark [row]/[col] as the active editing cell and clear any highlight.
  void setActive(int row, int col) {
    _activeRow = row;
    _activeCol = col;
    _setHighlight(-1, -1);
  }

  /// Highlight [row]/[col] for keyboard navigation (no editing), collapsing
  /// any range to that one cell.
  void setHighlighted(int row, int col) => _setHighlight(row, col);

  /// Jump to [row]/[col] as a highlighted cell, clearing the active cell.
  void goTo(int row, int col) {
    _activeRow = -1;
    _activeCol = -1;
    _setHighlight(row, col);
  }

  /// Move the range's far corner to [row]/[col], keeping the highlighted
  /// cell as the anchor.
  ///
  /// With nothing highlighted, the anchor becomes the cell being edited, or
  /// [row]/[col] itself. Extending always leaves edit mode.
  void extendTo(int row, int col) {
    if (!hasHighlight) {
      _highlightedRow = _activeRow >= 0 ? _activeRow : row;
      _highlightedCol = _activeCol >= 0 ? _activeCol : col;
    }
    _activeRow = -1;
    _activeCol = -1;
    _extentRow = row;
    _extentCol = col;
    notifyListeners();
  }

  /// Select the rectangle from the anchor [anchorRow]/[anchorCol] (which
  /// becomes the highlighted cell) to [extentRow]/[extentCol], leaving edit
  /// mode. Header clicks use this to select a whole row or column.
  void selectRange(int anchorRow, int anchorCol, int extentRow, int extentCol) {
    _activeRow = -1;
    _activeCol = -1;
    _highlightedRow = anchorRow;
    _highlightedCol = anchorCol;
    _extentRow = extentRow;
    _extentCol = extentCol;
    notifyListeners();
  }

  /// Clear active, highlighted, and range state.
  void clear() {
    _activeRow = -1;
    _activeCol = -1;
    _setHighlight(-1, -1);
  }

  void _setHighlight(int row, int col) {
    _highlightedRow = row;
    _highlightedCol = col;
    _extentRow = -1;
    _extentCol = -1;
    notifyListeners();
  }
}
