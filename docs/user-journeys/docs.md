# Docs Journeys

Covers the Docs page (`/docs`), the document editor for `.qdoc` files, and what opening a Word,
OpenDocument or RTF file from Files does (JN-DOC-007).

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

---

### JN-DOC-007: Open a Word, OpenDocument or RTF file

**Preconditions:** Signed in. Files holds `reports/q1.docx`. The same steps apply to a `.docm`, an `.odt` or an
`.rtf` in that folder.

**Steps:**

1. In Files, tap `q1.docx`.
2. Tap **Download**. Off web, tap **Open with…**.

**Expected result:**

- The generic viewer opens at `/view/reports/q1.docx` (JN-FB-019, JN-FB-043). The bar names the file. The page
  shows the document icon, the file name, and "DOCX file" with the size when the file has one.
- The pages are not drawn. There is no heading, table or image from the document, and no **Open as Quark doc**
  action.
- **Download** saves the file to the device. **Open with…** hands it to another app and is not offered on web.
- Docs (`/docs`) does not list the file. That list is `.qdoc` files only (JN-DOC-001).

**Notes:**

- `.docm`, `.odt` and `.rtf` are not classified as documents. The Kind column says File, the icon is the generic
  file icon, and the viewer says "DOCM file", "ODT file" or "RTF file". The page is otherwise the same.
- A legacy `.doc` takes that same generic page. Nothing reads it.
- A `.qdoc` opens the editor instead (JN-DOC-002).
- The Quark can read a `.docx`, `.docm`, `.odt` or `.rtf`, and can write a sibling `.qdoc` from one. The app
  calls neither, so a person never sees a rendered preview or a convert action (JN-FB-048).
