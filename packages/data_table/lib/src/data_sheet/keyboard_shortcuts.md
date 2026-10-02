# DataSheet Keyboard Shortcuts

Legend: ✅ implemented · 🔜 planned · ❌ out of scope for this package

Shortcuts are handled inside the `DataSheet` widget itself via its `Focus` +
`onKeyEvent` handler. They work regardless of whether a `DataSheetControlBar`
is present.

The entire key binding map is customizable — developers can supply their own
`DataSheetControlScheme` and even swap it at runtime. See
[Control Scheme Customization](#control-scheme-customization) below.

---

## Navigation

| Keys          | Action                                        | Status |
| ------------- | --------------------------------------------- | ------ |
| Arrow keys    | Move highlight one cell                       | ✅     |
| Tab           | Move highlight right; wraps at row end        | ✅     |
| Shift+Tab     | Move highlight left                           | ✅     |
| Enter         | Confirm edit / activate highlighted cell      | ✅     |
| Ctrl/Cmd+Home | Jump to first cell (row 0, col 0)             | ✅     |
| Ctrl/Cmd+End  | Jump to last cell                             | ✅     |
| Page Down     | Move highlight down by visible-page height    | 🔜     |
| Page Up       | Move highlight up by visible-page height      | 🔜     |
| Home          | Move highlight to first column in current row | ✅     |
| End           | Move highlight to last column in current row  | ✅     |

---

## Editing

| Keys                           | Action                                     | Status |
| ------------------------------ | ------------------------------------------ | ------ |
| Any printable key              | Open cell for editing (start typing)       | ✅     |
| F2                             | Enter edit mode for the highlighted cell   | ✅     |
| Escape                         | Cancel active edit, restore previous value | ✅     |
| Delete / Backspace             | Clear every cell in the selection          | ✅     |
| Ctrl/Cmd+Z                     | Undo last action                           | ✅     |
| Ctrl/Cmd+Y or Ctrl/Cmd+Shift+Z | Redo                                       | ✅     |

---

## Clipboard

| Keys       | Action                                                    | Status |
| ---------- | --------------------------------------------------------- | ------ |
| Ctrl/Cmd+C | Copy the selection                                        | ✅     |
| Ctrl/Cmd+X | Cut — copy then clear the selection                       | ✅     |
| Ctrl/Cmd+V | Paste at the selection's top-left; one value fills it all | ✅     |

The clipboard is the sheet's own, not the system clipboard: a copy keeps the
selection's raw values (formulas as written) and a paste writes them back
unchanged, clipped at the sheet edge. Each cut, paste and clear is one undo
step.

---

## Selection

| Keys               | Action                                          | Status |
| ------------------ | ----------------------------------------------- | ------ |
| Shift+Arrow        | Extend selection by one cell in arrow direction | ✅     |
| Ctrl/Cmd+A         | Select all cells                                | ✅     |
| Ctrl/Cmd+Shift+End | Extend selection to last used cell              | 🔜     |

The selection is a rectangle anchored at the highlighted cell, which keeps its
outline and is the cell typing edits. Shift+Arrow moves the opposite corner and
stops at the sheet edge; a plain arrow collapses the range and moves the
anchor. The name box in the formula bar shows the range, e.g. `B2:D9`.

Pointer selection, for reference alongside the keys:

| Pointer                           | Action                                      |
| --------------------------------- | ------------------------------------------- |
| Shift+click a cell                | Extend the range from the anchor to it      |
| Mouse drag                        | Select the cells the drag crosses           |
| Long-press, then drag (touch)     | Select a range; a quick swipe still scrolls |
| Click a column / row header       | Select the whole column / row               |
| Shift+click a column / row header | Extend to every column / row in between     |

---

## Data Operations

| Keys       | Action                                                            | Status |
| ---------- | ----------------------------------------------------------------- | ------ |
| Ctrl/Cmd+D | Fill down — copy the selection's top row through the rest of it   | ✅     |
| Ctrl/Cmd+R | Fill right — copy the selection's left column through the rest    | ✅     |
| Ctrl/Cmd+F | Open Find & Replace dialog                                        | 🔜     |
| Ctrl/Cmd+G | Open Go To Cell dialog                                            | 🔜     |

A selection one row tall fills down to the bottom of the sheet, and one column
wide fills right to its edge, so a single highlighted cell behaves as before.

---

## Row / Column Structural Operations

| Keys                 | Action                                | Status |
| -------------------- | ------------------------------------- | ------ |
| Ctrl/Cmd+Plus        | Insert row above highlighted cell     | ✅     |
| Ctrl/Cmd+Minus       | Delete every row the selection covers | ✅     |
| Ctrl/Cmd+Shift+Plus  | Insert column before highlighted cell | ✅     |
| Ctrl/Cmd+Shift+Minus | Delete every column it covers         | ✅     |

---

## Implementation Notes

- All shortcuts are dispatched through `DataSheetControlScheme` — the active
  scheme is resolved each key event via `widget.controlScheme ?? DataSheetControlScheme.defaults()`.
- `KeyboardShortcut.matches` checks `HardwareKeyboard.instance.isControlPressed || isMetaPressed`
  for the `ctrl` flag, so the same scheme works on Windows/Linux and macOS.
- Clipboard operations keep the copied cells in the `DataSheet`'s own state and
  write them through `DataSheetController.pasteValues`; the system clipboard is
  not involved.
- `_priorCellValue` is captured in `_activateCell` so that pressing Escape can
  restore the original value without touching undo history.
- Structural shortcuts delegate to `DataSheetController` methods that push an
  undo snapshot, so Ctrl+Z recovers inserted/deleted rows and columns.
- Page Up / Page Down require access to the scroll position and visible row
  count; they remain 🔜 until a `ScrollController` is wired into the view.
- Ctrl+F and Ctrl+G open dialogs; those are owned by the control bar rather than
  the sheet itself and remain 🔜 at the sheet level.

---

## Control Scheme Customization

### Motivations

- Different users have muscle memory for different editors (Excel, Google Sheets,
  Vim, etc.).
- Apps may need to reserve certain key combos for their own use.
- Accessibility requirements may mandate different bindings.

### Proposed API

`DataSheet` should accept an optional `controlScheme` parameter:

```dart
DataSheet(
  controller: myController,
  table: myTable,
  controlScheme: DataSheetControlScheme.excel(), // built-in preset
)
```

If omitted, `DataSheet` falls back to `DataSheetControlScheme.defaults()`.

### `DataSheetControlScheme`

A `DataSheetControlScheme` is a plain data class (no Flutter dependency) that
maps each logical **action** to one or more **key triggers**. Developers can:

1. Use a built-in preset (`defaults`, `excel`, `googleSheets`, `vim`).
2. Start from a preset and override individual bindings:

   ```dart
   final scheme = DataSheetControlScheme.excel().copyWith(
     undo: [KeyboardShortcut.ctrl(LogicalKeyboardKey.keyZ)],
     fillDown: [KeyboardShortcut.ctrl(LogicalKeyboardKey.keyD)],
   );
   ```

3. Build one entirely from scratch via the default constructor.

Swapping the scheme at runtime is supported — `DataSheet` reads it on each key
event, so passing a new scheme to a live widget via `setState` takes effect
immediately with no special handling.

### `KeyboardShortcut`

A lightweight value type describing a single trigger:

```dart
class KeyboardShortcut {
  final LogicalKeyboardKey key;
  final bool ctrl;   // also matches Cmd on macOS
  final bool shift;
  final bool alt;

  const KeyboardShortcut(this.key,
      {this.ctrl = false, this.shift = false, this.alt = false});

  factory KeyboardShortcut.ctrl(LogicalKeyboardKey key) =>
      KeyboardShortcut(key, ctrl: true);

  factory KeyboardShortcut.ctrlShift(LogicalKeyboardKey key) =>
      KeyboardShortcut(key, ctrl: true, shift: true);
}
```

### Named Actions

Each field of `DataSheetControlScheme` maps to one of the actions in this
document. The full set of action names (each takes `List<KeyboardShortcut>`):

| Field              | Default trigger       |
| ------------------ | --------------------- |
| `moveUp`           | Arrow Up              |
| `moveDown`         | Arrow Down            |
| `moveLeft`         | Arrow Left            |
| `moveRight`        | Arrow Right           |
| `moveNextCell`     | Tab                   |
| `movePreviousCell` | Shift+Tab             |
| `confirmEdit`      | Enter                 |
| `enterEditMode`    | F2                    |
| `cancelEdit`       | Escape                |
| `clearCell`        | Delete or Backspace   |
| `undo`             | Ctrl+Z                |
| `redo`             | Ctrl+Y / Ctrl+Shift+Z |
| `copy`             | Ctrl+C                |
| `cut`              | Ctrl+X                |
| `paste`            | Ctrl+V                |
| `selectAll`        | Ctrl+A                |
| `fillDown`         | Ctrl+D                |
| `fillRight`        | Ctrl+R                |
| `findReplace`      | Ctrl+F                |
| `goToCell`         | Ctrl+G                |
| `extendUp`         | Shift+Arrow Up        |
| `extendDown`       | Shift+Arrow Down      |
| `extendLeft`       | Shift+Arrow Left      |
| `extendRight`      | Shift+Arrow Right     |
| `jumpToFirst`      | Ctrl+Home             |
| `jumpToLast`       | Ctrl+End              |
| `jumpRowStart`     | Home                  |
| `jumpRowEnd`       | End                   |
| `pageUp`           | Page Up               |
| `pageDown`         | Page Down             |
| `insertRow`        | Ctrl+Plus             |
| `deleteRow`        | Ctrl+Minus            |
| `insertColumn`     | Ctrl+Shift+Plus       |
| `deleteColumn`     | Ctrl+Shift+Minus      |

### Saving and Loading Schemes

Serialization is left to the caller. `DataSheetControlScheme` should implement
`toJson()` / `fromJson()` so apps can:

- Persist a user's preferred scheme to `SharedPreferences`, a file, or a
  database.
- Ship pre-built scheme files (JSON) and load them at startup.
- Let users import/export schemes through their own settings UI.

`fromJson` fills an action missing from the JSON with its default binding, so
a scheme saved before an action existed picks it up; an action saved as an
empty list stays disabled.

The package does not bundle any particular persistence mechanism — keeping the
model serializable is enough.
