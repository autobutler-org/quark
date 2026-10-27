# Sheets Journeys

Covers the Sheets page (`/sheets`), the spreadsheet editor for `.qsheet` files, and opening an Excel workbook
from Files (JN-SH-007).

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

---

### JN-SH-007: Open an Excel, ODS or XLS workbook from Files

**Preconditions:** Signed in, on `/files`, with `data/budget.xlsx` and no `budget.qsheet` beside it.

**Steps:**

1. Tap `budget.xlsx`.
2. In **Convert to .qsheet?**, tap **Convert**.
3. Go back to Files, tap `budget.xlsx`, tap **Convert** again, and choose **Open existing**.
4. Go back to Files, tap `budget.xlsx`, tap **Convert** again, and choose **Replace**.

**Expected result:**

- The first dialog asks whether to convert "budget.xlsx" to a Quark spreadsheet (`.qsheet`) and says the
  original workbook will not be modified or deleted. The buttons are **Cancel** and **Convert**.
- **Convert** leaves `budget.xlsx` in place, writes `budget.qsheet` beside it, and opens that file in the
  spreadsheet editor (JN-SH-002).
- Every later tap asks **Convert to .qsheet?** again. After **Convert**, because `budget.qsheet` is already
  there, the dialog is **Spreadsheet already exists**: "budget.qsheet" is already here. Open it, or replace it
  with a fresh conversion of "budget.xlsx"? The buttons are **Cancel**, **Replace** and **Open existing**.
- **Open existing** opens the `.qsheet` and leaves the workbook alone. **Replace** converts again over that
  `.qsheet` and opens the new file. **Cancel** changes nothing.
- Sheets (`/sheets`) lists `.qsheet` files only. The workbook never appears there.

**Notes:**

- `.xlsm` asks the same way. The new name drops `.xlsx` or `.xlsm`.
- **Cancel** on the first dialog leaves the workbook unopened.
- A failure reads "Couldn't convert the file." A folder the account cannot write reads "You don't have
  permission to convert the file."
- Opening `/view/data/budget.xlsx`, or the file's `/files` URL, skips the question and shows the generic viewer
  (JN-FB-019). Tapping the row in Files is the path that asks.
- `.ods` and `.xls` are not a spreadsheet kind. Tapping one opens the generic viewer, labeled "ODS file" or
  "XLS file", and Files does not ask to convert it. The Quark can convert those two as well as `.xlsx` and
  `.xlsm`; the app only asks for the last two (JN-FB-048).
- A workbook inside an archive is downloaded, not converted (JN-FB-020).
