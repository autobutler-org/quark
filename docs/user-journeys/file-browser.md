# File Browser Journeys

Covers browsing, uploading, downloading, and managing files via the file browser at `/files`.

---

### JN-FB-001: Browse root file listing

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/files`.

**Expected result:**

- A list (or grid) of files and folders at the root of the quark's storage is shown.
- Empty state widget is displayed if no files exist yet.
- Storage usage footer is visible.

---

### JN-FB-002: Navigate into a folder

**Preconditions:** At least one folder exists in Files (JN-FB-001 passes).

**Steps:**

1. Navigate to `/files`.
2. Tap a folder in the listing.

**Expected result:**

- File listing updates to show the contents of that folder.
- URL updates to `/files/<folder-name>`.
- Breadcrumb updates to reflect the current path.

---

### JN-FB-003: Navigate up via breadcrumb

**Preconditions:** User is inside a subfolder (JN-FB-002 complete).

**Steps:**

1. Tap a parent segment in the breadcrumb.

**Expected result:**

- File listing updates to show the parent folder's contents.
- URL updates to match the parent path.

---

### JN-FB-004: Toggle between list view and grid view

**Preconditions:** User is at `/files`.

**Steps:**

1. Tap the grid/list toggle button in the top bar.

**Expected result:**

- View switches from list to grid (or vice versa).
- File names and icons remain correct in the new layout.

---

### JN-FB-005: Toggle unified vs. per-device view

**Preconditions:** Multiple storage devices are connected.

**Steps:**

1. Navigate to `/files`.
2. Tap the unified/device-grouped toggle.

**Expected result:**

- In unified mode: files from all devices are shown interleaved without section headers.
- In device-grouped mode: files are grouped under per-device section headers.

---

### JN-FB-006: Upload a file via file picker

**Preconditions:** User is logged in. A file is available on the client device.

**Steps:**

1. Navigate to `/files` (or any subfolder).
2. Tap the **upload** FAB or button.
3. Select a file from the system file picker.

**Expected result:**

- Upload progress indicator is shown.
- On completion, the file appears in the current directory listing.

---

### JN-FB-007: Upload a file via drag-and-drop (desktop/web)

**Preconditions:** User is on a platform that supports drag-and-drop.

**Steps:**

1. Navigate to `/files`.
2. Drag a file from the OS file manager onto the file browser drop zone.

**Expected result:**

- Drop zone highlights when file is hovered over it.
- File uploads on drop.
- File appears in the listing after upload completes.

---

### JN-FB-008: Download a file

**Preconditions:** At least one file exists in Files.

**Steps:**

1. Navigate to `/files`.
2. Long-press (mobile) or right-click / use the context menu (desktop/web) on a file.
3. Select **Download**.

**Expected result:**

- File download begins.
- File is saved to the client device's downloads location.

---

### JN-FB-009: Create a new folder

**Preconditions:** User is logged in, at any path in `/files`.

**Steps:**

1. Tap the **New folder** button or FAB action.
2. Enter a folder name in the dialog.
3. Confirm.

**Expected result:**

- New folder appears in the current directory listing.
- Folder is navigable (JN-FB-002).

---

### JN-FB-010: Rename a file or folder

**Preconditions:** At least one file or folder exists in Files.

**Steps:**

1. Open the context menu on a file or folder.
2. Select **Rename**.
3. Enter a new name.
4. Confirm.

**Expected result:**

- Item appears in the listing with the new name.
- Old name no longer appears.

---

### JN-FB-011: Move a file or folder

**Preconditions:** At least two folders exist in Files.

**Steps:**

1. Open the context menu on a file or folder.
2. Select **Move**.
3. Choose a destination folder in the picker.
4. Confirm.

**Expected result:**

- Item disappears from the source directory listing.
- Item appears in the destination directory.

---

### JN-FB-012: Delete a single file

**Preconditions:** At least one file exists in Files.

**Steps:**

1. Open the context menu on a file.
2. Select **Delete**.
3. Confirm the deletion prompt.

**Expected result:**

- File no longer appears in the listing.

---

### JN-FB-013: Batch delete multiple files

**Preconditions:** Multiple files exist in Files.

**Steps:**

1. Navigate to `/files`.
2. Enter multi-select mode (long-press a file on mobile, or use the selection checkbox on desktop/web).
3. Select two or more files.
4. Tap **Delete selected**.
5. Confirm the deletion prompt.

**Expected result:**

- All selected files are removed from the listing.
- Unselected files remain.
- App exits selection mode after deletion.

---

### JN-FB-014: Search for a file by name

**Preconditions:** At least one file exists in Files.

**Steps:**

1. Navigate to `/files`.
2. Tap the search icon.
3. Enter a partial or full filename.

**Expected result:**

- Results update in real time (or on submit) to show matching files.
- Non-matching files are hidden.
- Clearing the search restores the full listing.

---

### JN-FB-015: Open an image file in the image viewer

**Preconditions:** An image file (jpg, png, etc.) exists in Files.

**Steps:**

1. Navigate to the folder containing the image.
2. Tap the image file.

**Expected result:**

- Image viewer opens (`ImageViewerPage`).
- Image is displayed correctly.
- User can navigate back to the file browser.

---

### JN-FB-016: Open a video file in the video viewer

**Preconditions:** A video file exists in Files.

**Steps:**

1. Tap the video file in the file browser.

**Expected result:**

- Video viewer opens (`VideoViewerPage`).
- Video is playable.

---

### JN-FB-017: Open and play an audio file

**Preconditions:** An audio file exists in Files.

**Steps:**

1. Tap the audio file in the file browser.

**Expected result:**

- Audio player opens (`AudioPlayerPage`).
- Playback controls are functional.

---

### JN-FB-018: Open a plaintext file in the plaintext editor

**Preconditions:** A `.txt` (or similar plaintext) file exists in Files.

**Steps:**

1. Tap the file in the file browser.

**Expected result:**

- Plaintext editor opens (`PlaintextEditorPage`) at the correct path.
- File contents are displayed and editable.

---

### JN-FB-019: Open a generic/unsupported file (native open)

**Preconditions:** A file of a type without a dedicated viewer (e.g. `.zip`, `.pdf`) exists in Files.

**Steps:**

1. Tap the file.

**Expected result:**

- App attempts to open the file with the OS native handler.
- If no handler is available, a clear error or fallback message is shown.

---

### JN-FB-020: Browse inside an archive

**Preconditions:** A `.zip` or other supported archive file exists in Files.

**Steps:**

1. Navigate to the archive file in the file browser.
2. Tap the archive.

**Expected result:**

- File browser enters archive navigation mode.
- Contents of the archive are listed.
- User can navigate subfolders within the archive.

---

### JN-FB-021: Extract an archive

**Preconditions:** A supported archive file exists in Files.

**Steps:**

1. Open the context menu on the archive file.
2. Select **Extract**.

**Expected result:**

- Archive is extracted on the quark.
- Extracted contents appear in the current directory.

---

### JN-FB-022: View recent files

**Preconditions:** User has opened or uploaded files previously.

**Steps:**

1. Navigate to `/files` root.

**Expected result:**

- A "Recent files" section is visible above the main listing.
- Recently accessed files are shown with correct names.

---

### JN-FB-023: Filter files by storage device

**Preconditions:** Multiple storage devices are connected.

**Steps:**

1. Navigate to `/files`.
2. Open the device filter (header or filter UI).
3. Deselect one or more devices.

**Expected result:**

- Only files from the selected devices are shown.
- Re-selecting a device restores its files.

---

### JN-FB-024: Real-time file update via WebSocket

**Preconditions:** User has `/files` open. Another client or the quark uploads a file concurrently.

**Steps:**

1. Have a second client (or the quark itself) upload a new file.

**Expected result:**

- New file appears in the file listing without a manual refresh.

---

### JN-FB-025: Deep-link directly to a subfolder

**Preconditions:** A subfolder `photos/2024` exists in Files.

**Steps:**

1. Navigate directly to `/files/photos/2024`.

**Expected result:**

- File browser opens at `photos/2024`.
- Breadcrumb shows the correct path.

---

### JN-FB-026: Upload photos from the Camera Roll on iOS

**Preconditions:** User is on iOS (Safari, the installed PWA, or the native app). Photos or videos exist in the Camera Roll.

**Steps:**

1. Navigate to `/files` (or any subfolder).
2. Tap the upload control (the **Create** FAB on a phone, the **Upload** chip on iPad).
3. Choose **Upload photos** / **Photos** — it is the first option.
4. Select one or more photos or videos from the Photos library.

**Expected result:**

- The Photos library opens, not the Files app.
- Selected items upload to the current directory.
- **Upload files** remains available as a separate source for documents.

**Notes:** iOS's document picker is the Files app and cannot see the Camera Roll. Photos is a distinct source for that reason. Other platforms keep a single Files picker, which already includes the gallery.
