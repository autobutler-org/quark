# Trash Journeys

Covers the Trash page (`/trash`) — files and folders deleted from Files, waiting to be restored or purged. Every
delete in Files moves the item here; the butler deletes anything older than its retention period (30 days) for good
on an hourly sweep.

---

### JN-TR-001: Open the trash

**Preconditions:** Logged in. At least one file has been deleted from Files (JN-FB-012).

**Steps:**

1. Open the drawer.
2. Tap **Trash**.

**Expected result:**

- The app navigates to `/trash`, and **Trash** is marked in the drawer.
- The deleted file is listed in the same list layout as Files, newest deletion first.
- Each row shows the folder it was deleted from ("From /Documents") and how many days are left before it is
  deleted for good ("12 days left").

**Notes:** An empty trash shows "Trash is empty" and how long deleted files are kept.

---

### JN-TR-002: Trashed files do not open

**Preconditions:** At least one file is in the trash.

**Steps:**

1. Tap a trashed file.
2. Open its context menu.

**Expected result:**

- Nothing opens: no viewer, no editor, no preview.
- The context menu offers only **Restore** and **Delete permanently**.

**Notes:** Folders do open; see JN-TR-010.

---

### JN-TR-003: Restore an item

**Preconditions:** A file is in the trash, and nothing now sits at its original path.

**Steps:**

1. Open the context menu on the file.
2. Select **Restore**.

**Expected result:**

- A snack bar reads "Restored 1 item".
- The file leaves the trash and is back in its original folder in Files.

---

### JN-TR-004: Restore onto an occupied path

**Preconditions:** A file is in the trash, and a new file with the same name has since been created in its original
folder.

**Steps:**

1. Open the context menu on the trashed file.
2. Select **Restore**.

**Expected result:**

- A snack bar reads "Something is already at that location. Move or rename it, then restore again."
- The trashed file stays in the trash, and the new file is untouched — a restore never overwrites.

---

### JN-TR-005: Restore or delete several items at once

**Preconditions:** Several items are in the trash.

**Steps:**

1. Long-press an item to enter selection mode.
2. Select two or more items (or tap **Select all**).
3. Tap the restore button — or the delete button, then confirm **Delete permanently**.

**Expected result:**

- Every selected item is restored (or deleted for good), and a snack bar gives the count.
- The app leaves selection mode.

---

### JN-TR-006: Delete an item permanently

**Preconditions:** A file is in the trash.

**Steps:**

1. Open the context menu on the file.
2. Select **Delete permanently**.
3. Confirm the prompt.

**Expected result:**

- The prompt warns that the file will be deleted for good.
- After confirming, the file leaves the trash and cannot be restored.
- Cancelling the prompt leaves the file in the trash.

---

### JN-TR-007: Empty the trash

**Preconditions:** Several items are in the trash.

**Steps:**

1. Tap the **Empty trash** button in the top bar.
2. Confirm the prompt.

**Expected result:**

- Every item in the trash of the devices shown is deleted for good.
- The page shows "Trash is empty".

**Notes:** The button is disabled while the trash is empty, and only shown at the top level of the trash: inside a
trashed folder it would read as emptying that folder.

---

### JN-TR-008: Filter the trash by storage device

**Preconditions:** More than one storage device is attached, each with something in its trash.

**Steps:**

1. Navigate to `/trash`.
2. Tap a device chip to hide that device's trash.

**Expected result:**

- Items from the hidden device leave the list; the others stay.
- Empty trash only empties the devices still shown.

**Notes:** Mirrors the Files device filter (JN-FB-023).

---

### JN-TR-009: Trash updates live

**Preconditions:** The Trash page is open in one client.

**Steps:**

1. In a second client, delete a file from Files.

**Expected result:**

- The file appears in the first client's trash without a manual refresh.

**Notes:** Driven by the `trash_changed` event on `/api/v0/events`, which also fires when the hourly purge removes
expired items.

---

### JN-TR-010: Browse a trashed folder

**Preconditions:** A folder holding files and a subfolder has been deleted from Files.

**Steps:**

1. Navigate to `/trash`.
2. Tap the trashed folder.
3. Tap the subfolder inside it.
4. Press the browser back button, or tap the folder's name in the breadcrumbs.

**Expected result:**

- Each tap opens the folder in the same list layout, and the URL follows it: `/trash/<trash name>/<path inside>`,
  with `?serial=` for a USB drive. Opening the URL directly lands on the same folder.
- Breadcrumbs show the trashed folder's name and the path inside it; the home glyph returns to the trash root.
- Each row reads where it would be restored to and how many days its trashed folder has left
  ("From /Pictures/album · 12 days left").
- Files inside still do not open (JN-TR-002); their context menu offers only **Restore** and **Delete permanently**.
- **Empty trash** and the device chips are not shown inside a folder.

---

### JN-TR-011: Restore or delete something from inside a trashed folder

**Preconditions:** A trashed folder is open (JN-TR-010).

**Steps:**

1. Open the context menu on a file inside it and select **Restore** — or long-press to select several and tap the
   restore button.
2. Open the context menu on another file, select **Delete permanently**, and confirm.

**Expected result:**

- The restored file is back in Files at its original location inside the folder, which is recreated if it no longer
  exists. The rest of the trashed folder stays in the trash.
- The deleted file leaves the trashed folder for good; nothing else is touched.
- If something now occupies the restored file's original path, the snack bar reads "Something is already at that
  location. Move or rename it, then restore again." and nothing is restored (JN-TR-004).

---

### JN-TR-012: The open folder disappears

**Preconditions:** A folder inside a trashed folder is open in one client.

**Steps:**

1. In a second client, restore the whole trashed folder (or delete it permanently).

**Expected result:**

- The first client does not show an error. On the `trash_changed` refresh it moves up to the nearest level that
  still exists — here the trash root — and the URL follows.

**Notes:** The same happens when the hourly purge removes the trashed folder, or when a deep link names a folder that
is not in the trash.
