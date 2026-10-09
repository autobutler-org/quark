# Sheets Journeys

Covers the Sheets page (`/sheets`) and the spreadsheet editor for `.qsheet` files.

---

### JN-SH-001: Browse spreadsheets list

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/sheets`.

**Expected result:**

- A list of `.qsheet` files stored on the quark is displayed.
- Empty state is shown if no spreadsheets exist.

---

### JN-SH-002: Open an existing spreadsheet

**Preconditions:** At least one `.qsheet` file exists in Files.

**Steps:**

1. Navigate to `/sheets`.
2. Tap a spreadsheet in the list.

**Expected result:**

- Spreadsheet editor opens (`SpreadsheetEditorPage`) with the file contents loaded.
- URL updates to `/sheets/<path-to-file>?from=/sheets`.
- The editor's back arrow, or a system back, returns to the Sheets list. A spreadsheet opened from Files returns to
  its folder, as a deep link does (#2403).

---

### JN-SH-003: Create a new spreadsheet

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/sheets`.
2. Tap the **New spreadsheet** FAB or button.
3. Enter a filename/title.
4. Confirm.

**Expected result:**

- New `.qsheet` file is created on the quark.
- Editor opens for the new file with an empty grid.

---

### JN-SH-004: Edit a cell and save

**Preconditions:** A spreadsheet is open (JN-SH-002 or JN-SH-003).

**Steps:**

1. Tap a cell in the grid.
2. Enter a value.
3. Confirm the cell edit (tap away or press Enter).
4. Trigger save (explicit save button, or autosave).

**Expected result:**

- Cell value is updated in the grid.
- Changes are persisted to the quark.
- Re-opening the spreadsheet shows the saved content.

---

### JN-SH-005: Deep-link directly to a spreadsheet

**Preconditions:** A `.qsheet` file exists at `data/budget.qsheet`.

**Steps:**

1. Navigate directly to `/sheets/data/budget.qsheet`.

**Expected result:**

- Spreadsheet editor opens with the correct file.

---

### JN-SH-006: Open spreadsheet from a specific storage device

**Preconditions:** Multiple devices are connected. A spreadsheet exists on a non-default device.

**Steps:**

1. Navigate to `/sheets/<path>?serial=<device-serial>`.

**Expected result:**

- Editor opens the file from the specified device.
