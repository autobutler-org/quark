# DataSheet Control Bar — Intended Features

This file documents the intended capabilities for the `DataSheetControlBar` companion widget. The control bar is optional
— apps may provide their own controls and call methods on `DataSheetController` directly.

Legend: ✅ implemented · 🔜 planned · ❌ out of scope for this package

## Essential Controls

- ✅ Insert Row Before / After — `insertRowAt(index)`
- ✅ Insert Column Before / After — `insertColumnAt(index)`
  - With no selection these anchor to the sheet edges — "before" targets the top/left, "after" appends — so the bar needs
    no separate append button. Column inserts are disabled while the sheet has no rows, since columns live inside rows.
- ✅ Delete Row — `deleteRowAt(index, count:)`, every row the selection covers
- ✅ Delete Column — `deleteColumnAt(index, count:)`, every column the selection covers

## Editing & Bulk Operations

- ✅ Undo / Redo — snapshot-based, 100-step depth
- ✅ Duplicate Row — `duplicateRow(index)`
- ✅ Duplicate Column — `duplicateColumn(index)`
- ✅ Clear Row — `clearRow(index, count:)` (empties all values in every selected row)
- ✅ Clear Column — `clearColumn(index, count:)`
- ✅ Clear Cell / Range — `clearCell(row, col)`, `clearRange(range)`
- ✅ Fill Down — `fillDownRange(range)` copies the selection's top row through the rest of it; a one-row selection fills
  to the bottom of the sheet
- ✅ Fill Right — `fillRightRange(range)` copies the selection's left column through the rest of it; a one-column
  selection fills to the right edge
- ✅ Copy / Cut / Paste — `data_sheet_copy`, `data_sheet_cut`, `data_sheet_paste`; act on the selection through the
  bar's `clipboard` (see Clipboard below)
- ✅ Clear selected cells — `data_sheet_clear_range`, `clearRange(range)`, one undo step
- ✅ Bulk Edit — paste one value over a range (`pasteValues(range, [[value]])`) to fill it

## Selection & Navigation

- ✅ Go To Cell — dialog, sets selection via `DataSheetSelectionModel.goTo(row, col)`
- ✅ Select All — Ctrl/Cmd+A, `selection.selectRange(...)`; Escape clears the selection
- ✅ Rectangular selection — `DataSheetSelectionModel` keeps an anchor (the highlighted cell) and an extent; `range`
  returns the normalized `CellRange` and `extendTo` / `selectRange` move it. Drag (mouse), long-press drag (touch),
  Shift+click, Shift+arrows, and column/row header clicks all drive it, and the formula bar's name box shows `B2:D9`.
  Range cells and their headers are tinted from the theme's primary color.
- ✅ Range operations — copy, cut, paste, clear, fill, and row/column delete and clear act on the whole selection
  (`selection.contextRange`), each as one undo step. Insert, duplicate, and sort still anchor to the highlighted cell.
- 🔜 Find (highlight results) — `findCells()` exists on controller; UI highlight not yet wired

## Clipboard

The package never touches the platform clipboard. `DataSheet` and `DataSheetControlBar` both take a
`DataSheetClipboard` — a `read` and a `write` the app supplies — and default to the shared in-app
`DataSheetClipboard.memory`. Quark's `SheetTabView` passes one backed by `lib/utils/clipboard_utils.dart`, falling back
to memory where the browser blocks the clipboard.

- `rangeToTsv(range)` — the range's raw text (formulas copy as formulas; their references do not shift), tab-separated. A value
  holding a tab, newline or `"` is quoted with its quotes doubled, as Google Sheets and Excel write it.
- `DataSheetController.parseTsv(text)` — reads that format back: quoted fields may hold tabs and newlines, LF and CRLF
  both end a row, one trailing line ending is dropped, and ragged rows are padded.
- `pasteTsv(text, range)` — parses, then `pasteValues(range, rows)`: one undo step, then selects what it wrote. The block lands at the range's top-left. When
  the range is a whole number of blocks tall and wide the block tiles it (so one value fills the range); otherwise it
  pastes once at its own size, adding rows and columns past the sheet's edge.

## Sort, Filter & Transform

- ✅ Sort by column — `sortByColumn(col, ascending)` with dialog
- ✅ Remove Duplicate Rows — `removeDuplicateRows()`
- 🔜 Filter by column value / predicate
- 🔜 Apply column transformations (trim, case, parse)

## Find & Replace

- ✅ Find — `findCells(query)` on controller
- ✅ Replace All — `replaceCells(from, to)` with dialog, case-sensitive toggle

## Import / Export / Persistence

- ✅ Export CSV — `exportCsv()` returns RFC-4180 string; shown in copy-able dialog
- ✅ Import CSV — `loadFromCsv(csv)` replaces table; dialog accepts pasted text
- 🔜 Export to Excel / spreadsheet format
- 🔜 Save / Load named templates

## View & Layout

- ✅ Pixel column widths and row heights — `columnWidths` / `rowHeights`, `setColumnWidth`, `setRowHeight`. These
  replaced flex factors: `fromTable(columnFlex:)` and a saved `columnFlex` key still load, each factor becoming that
  many default widths, and saved lists of the wrong length or with bad values are fitted to the sheet.
- ✅ Drag-to-resize columns and rows — drag a column header's right edge or a row number's bottom edge
  (`col_resize_<c>`, `row_resize_<r>`). `beginResize()` makes each drag one undo step. A selected header's edge grows
  a 24px grip so a phone can reach it: tap the header, then drag the grip.
- ✅ Auto-fit — double-click (or double-tap) a resize edge; `autoSizeColumn` / `autoSizeRow`, each one undo step
- ✅ Freeze rows / columns — the Freeze menu (`data_sheet_freeze`): none, 1, 2, or up to the selected row or column;
  `setFrozenRows` / `setFrozenColumns`, each one undo step. Frozen rows and columns stay put, with the column headers and row
  numbers, while the rest scrolls; a divider marks the edge, and frozen panes never cover more than 75% of the grid.
  Inserting or deleting inside the frozen band moves its edge.
- ✅ Layout persistence — `layoutToJson()` / `DataSheetController.fromLayoutJson()`: `columnWidths`, `rowHeights`,
  `frozenRows`, `frozenColumns`, saved beside the data in each `.qsheet` tab. Missing keys load as defaults.
- 🔜 Toggle gridlines visibility
- 🔜 Column type / format metadata (text, number, date)

## Advanced Data Features

- 🔜 Formula bar / expression evaluation
- 🔜 Per-cell validation rules
- 🔜 Cell formatting (font weight, alignment, number format)
- 🔜 Conditional formatting rules

## UX / Accessibility

- ✅ Tooltip labels on every toolbar button
- ✅ Disabled states — buttons are null (disabled) when no row/column is selected
- ✅ Context-sensitive enabling — row/column buttons require a cell to be highlighted
- 🔜 Keyboard shortcuts for toolbar actions
- 🔜 Localization / i18n

## Extensibility & Integration

- ✅ Accepts `DataSheetController` (required)
- ✅ Selection model (`DataSheetSelectionModel`) exposed on the controller so custom bars can read it
- 🔜 `onAction` callback hooks for telemetry
- 🔜 Custom builder slot for replacing individual button groups

## Architecture Notes

- `DataSheetSelectionModel` is owned by `DataSheetController` and propagates its changes through the controller's `notifyListeners`,
  so any `ListenableBuilder(listenable: controller)` reacts to both data and selection changes.
- The control bar uses `ListenableBuilder` internally; no external state management needed.
- Library widgets do not embed `MaterialApp` or assume `Directionality` — the host app provides the material tree.
- All mutating controller methods push an undo snapshot before making changes.
