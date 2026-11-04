# Books Journeys

Covers the Books page (`/books`): every PDF and EPUB the Quark holds, in one list, each opening in the file viewer
Files uses (#1678).

---

### JN-BK-001: Browse books

**Preconditions:** User is logged in. At least one `.pdf` or `.epub` exists somewhere in Files.

**Steps:**

1. Open the drawer and tap **Books**, or navigate to `/books`.

**Expected result:**

- Every `.pdf` and `.epub` the user can read is listed by file name, whatever folder it is in and whichever
  drive it is on, the internal drive and each attached drive.
- Each row shows the file name, and under it the folder it is in and its size.
- The app bar's refresh button, beside the brand button, fetches the list again.

**Notes:** The list is `GET /api/v0/books`. A file the user cannot read is left out, per drive. Rows on the
internal drive are keyed `book_tile_<path>`; a row on another drive is `book_tile_<serial>_<path>`.

---

### JN-BK-002: Open a book

**Preconditions:** JN-BK-001 passes.

**Steps:**

1. On `/books`, tap a book.
2. Close the viewer with its back button.

**Expected result:**

- The book opens at its `/view/<path>` URL (JN-FB-043), on the drive it is on: a `.pdf` in the PDF viewer
  (JN-FB-045), an `.epub` in the generic viewer (JN-FB-019), which offers **Download** and, off web, **Open with…**.
- Closing the viewer returns to `/books`, not to the book's folder in Files.

**Notes:** The viewer's URL carries `?from=/books`, and `?serial=` when the book is on an attached drive. Opened
without `from` — from Files, a pasted link — the viewer closes into the book's folder as before.

---

### JN-BK-003: No books yet

**Preconditions:** User is logged in. No `.pdf` or `.epub` exists in Files.

**Steps:**

1. Navigate to `/books`.

**Expected result:**

- An empty state reads "No books yet", with "PDF and EPUB files you add to Files show up here." under it.

---

### JN-BK-004: The book list fails to load

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/books` while the Quark answers the listing with an error.
2. Tap **Retry**.

**Expected result:**

- The page reads "Couldn't load your books." with a **Retry** button, and never shows the Quark's raw error.
- With the Quark unreachable, the disconnected view shows instead, as on Slides.
- Retry fetches the list again.

---

### JN-BK-005: An added PDF shows up

**Preconditions:** User is logged in. Auto-refresh may be off.

**Steps:**

1. Add a `.pdf` or `.epub` in Files, on the internal drive or an attached drive.
2. Open `/books`, or stay there if it is already open.

**Expected result:**

- The file appears in the list without waiting for the next poll and without a manual refresh, including when
  auto-refresh is off.
- Tapping it opens that file on the drive it was added to (JN-BK-002).

**Notes:** An upload, move, delete or restore anywhere in Files refreshes the list. A file the user cannot read
on that drive stays off it.
