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

- ✅ Column flex configuration — `setColumnFlex`, `updateColumnFlexAt`
- 🔜 Freeze rows / columns (sticky header)
- 🔜 Toggle gridlines visibility
- 🔜 Drag-to-resize columns
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
