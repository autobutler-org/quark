# Docs Journeys

Covers the Docs page (`/docs`) and the document editor for `.qdoc` files.

---

### JN-DOC-001: Browse documents list

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/docs`.

**Expected result:**

- A list of `.qdoc` files stored on the quark is displayed.
- Empty state is shown if no documents exist.

---

### JN-DOC-002: Open an existing document

**Preconditions:** At least one `.qdoc` file exists in Files.

**Steps:**

1. Navigate to `/docs`.
2. Tap a document in the list.

**Expected result:**

- Document editor opens (`DocumentEditorPage`) with the file contents rendered.
- URL updates to `/docs/<path-to-file>?from=/docs`.
- The editor's back arrow, or a system back, returns to the Docs list. A document opened from Files returns to its
  folder, as a deep link does (#2403).

---

### JN-DOC-003: Create a new document

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/docs`.
2. Tap the **New document** FAB or button.
3. Enter a filename/title.
4. Confirm.

**Expected result:**

- New `.qdoc` file is created on the quark.
- Editor opens for the new file.

---

### JN-DOC-004: Edit and save a document

**Preconditions:** A document is open in the editor (JN-DOC-002 or JN-DOC-003).

**Steps:**

1. Make changes to the document content.
2. Trigger save (explicit save button, or autosave).

**Expected result:**

- Changes are persisted to the quark.
- Re-opening the document shows the saved content.

---

### JN-DOC-005: Deep-link directly to a document

**Preconditions:** A `.qdoc` file exists at `reports/q1.qdoc`.

**Steps:**

1. Navigate directly to `/docs/reports/q1.qdoc`.

**Expected result:**

- Document editor opens with the correct file.
- No intermediate navigation step required.

---

### JN-DOC-006: Open document from a specific storage device

**Preconditions:** Multiple devices are connected. A document exists on a non-default device.

**Steps:**

1. Navigate to `/docs/<path>?serial=<device-serial>`.

**Expected result:**

- Editor opens the file from the specified device.
