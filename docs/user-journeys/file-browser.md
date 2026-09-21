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
2. Long-press a file, or open its three-dot menu.
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
3. Confirm the **Move to Trash?** prompt.

**Expected result:**

- The prompt says the file moves to Trash and can be restored for 30 days — it never calls the delete
  permanent, because it is not (#2049).
- File no longer appears in the listing.
- File appears in the trash, where it can be restored (JN-TR-001, JN-TR-003).

---

### JN-FB-013: Batch delete multiple files

**Preconditions:** Multiple files exist in Files.

**Steps:**

1. Navigate to `/files`.
2. Enter multi-select mode with the **Select files** button in the toolbar.
3. Select two or more files.
4. Tap **Delete selected**.
5. Confirm the deletion prompt.

**Expected result:**

- All selected files are removed from the listing and moved to the trash (JN-TR-001).
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
2. As the owner of a folder, share it with the user, then stop sharing it.

**Expected result:**

- New file appears in the file listing without a manual refresh.
- The shared folder appears in the user's listing, then leaves it, without a manual refresh.
- If the user had the folder open when it stopped being shared, the page shows **Folder not found** with a way back
  to `/files`.

**Notes:** Uploads, deletes, moves and new folders each publish their own event. A sharing change, or a change to a
group the user is in, publishes `access_changed`.

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

---

### JN-FB-027: Share a folder with an account

**Preconditions:** User owns the folder `Recipes`, or is an admin. Another account, `bob`, can sign in.

**Steps:**

1. Open the context menu on `Recipes` and select **Share…**.
2. Under **Share with**, search for `bob` and tap his row.
3. Choose **Can edit** and tap **Share**.

**Expected result:**

- The share sheet opens, titled **Share Recipes**, listing who has access.
- After step 3 **bob** is listed under **Who has access** as **Can edit**.
- `Recipes` appears in bob's Files without a refresh (JN-FB-024), and bob can add, rename and delete inside it.

**Notes:**

- **Can view** lets someone open and download; **Owner** also lets them change who has access, including making other
  owners.
- **Share…** isn't offered inside an archive or in the trash.

---

### JN-FB-028: Share with a group, or with everyone

**Preconditions:** User owns the folder `Recipes`. A group `Family` exists (JN-USR-016).

**Steps:**

1. Open **Share…** on `Recipes`.
2. Pick **Family**, keep **Can view**, and tap **Share**.
3. Pick **everyone** and tap **Share**.

**Expected result:**

- Groups are listed ahead of accounts among the choices, **everyone** first, reading **Every account**.
- After step 2 every member of **Family** can open `Recipes`; after step 3 every account can.
- Someone added to **Family** later gets the same access (JN-USR-018).

---

### JN-FB-029: Change or remove access

**Preconditions:** User owns `Recipes`, which is shared with `bob` at **Can edit** and with `cy` as **Owner**.

**Steps:**

1. Open **Share…** on `Recipes`.
2. Open bob's level menu and choose **Can view**.
3. Tap the remove button on bob's row.
4. Tap the remove button on cy's row, read the confirmation, and tap **Remove**.

**Expected result:**

- After step 2 bob can still open `Recipes` but no longer change it.
- After step 3 bob is no longer listed, and `Recipes` leaves his Files.
- Step 4 asks first, because an item with no owner left can only be managed by admins. **Cancel** changes nothing.
- Giving an owner a lower level asks the same way.

---

### JN-FB-030: Access inherited from a folder

**Preconditions:** The folder `Family` is shared with `bob` at **Can edit** and holds a subfolder, `Recipes`. User owns
`Family`.

**Steps:**

1. Open **Share…** on `Family/Recipes`.
2. Move `Recipes` out of `Family`, then open **Share…** on it again.

**Expected result:**

- After step 1 bob is listed under **Inherited access**, reading "Can edit · From Family", with no level menu and no
  remove button: that access can only be changed on `Family`.
- The same account can also have access set on `Recipes` itself, listed separately under **Who has access**.
- After step 2 the inherited row is gone: an item moved out of a shared folder no longer has that folder's access.

**Notes:**

- Access adds up through the folders an item is in, so a subfolder can't be more private than the folder that holds
  it.
- Access set on a drive's root folder reads "From /".

---

### JN-FB-031: Only owners and admins manage sharing

**Preconditions:** `Recipes` is shared with `bob` at **Can edit**. User is signed in as `bob`, who is not an admin.

**Steps:**

1. Open the context menu on `Recipes` and select **Share…**.

**Expected result:**

- The sheet reads "Only the owner or an admin can change sharing." and shows nothing else.

**Notes:**

- The same happens at **Can view**. Only an owner of the item, or of a folder that holds it, or an admin, sees and
  changes who has access.

---

### JN-FB-032: Your own ownership stays yours

**Preconditions:** User owns `Recipes` through access set on it, and is not an admin.

**Steps:**

1. Open **Share…** on `Recipes`.
2. Find your own row under **Who has access**.

**Expected result:**

- Your row reads **Owner**, and its level menu and remove button are turned off, so you can't lock yourself out.
- Another owner, or an admin, can still change or remove it.

---

### JN-FB-033: A member lands in their own files

**Preconditions:** Signed in as `bob`, who is not an admin and whose home, `users/bob`, has files in it.

**Steps:**

1. Navigate to `/files`.
2. Read the breadcrumb.
3. Tap **Up**, then **Back**.
4. Navigate directly to `/files/users/bob/Trip`.

**Expected result:**

- The listing opens on bob's own files, not on a root holding nothing but `users` and `groups`.
- A row of shortcuts is shown: **My files** and **Groups**, so nobody walks through `users` or `groups` to get
  anywhere.
- The breadcrumb reads `users` / `bob`, and the `users` crumb is plain text rather than a link: it is a waypoint bob
  can't open.
- **Up** and **Back** are turned off in bob's own files, so neither strands him in `users`.
- Step 4 opens `users/bob/Trip`: a path in the URL always wins, so deep links and reloads are untouched.

**Notes:**

- The address bar still reads `/files` after step 1. Tapping a shortcut or a folder updates it as usual (JN-FB-002).
- Recent files, on a screen wide enough for it (JN-FB-022), is shown on the folder the account lands on.
- A session recorded before the app kept a username lands at the real root instead.

---

### JN-FB-034: An admin lands at the real root

**Preconditions:** Signed in as an admin.

**Steps:**

1. Navigate to `/files`.
2. Tap **My files**, then **All files**.

**Expected result:**

- The listing opens at the real root, holding `users`, `groups` and whatever else is on the quark: an admin can reach
  everything, so the root is a real place for them.
- The shortcuts read **My files**, **Groups** and **All files**.
- **My files** opens the admin's own home, `users/<username>`; every admin has one. **All files** returns to the root.

**Notes:**

- Whether the account is an admin is answered by the quark after the page is built, so a reload can show an admin
  their own files for a moment before moving them to the root. It only moves them if they haven't navigated yet.

---

### JN-FB-035: Open a group's folder

**Preconditions:** Signed in as `bob`, who is not an admin and is a member of the group `Family` (JN-USR-018).

**Steps:**

1. Navigate to `/files` and tap **Groups**.
2. Open `Family`.
3. Upload a file into it (JN-FB-006).

**Expected result:**

- **Groups** opens `groups`, listing `Family` and `everyone` — the group folders bob's groups reach, not every group
  on the quark.
- `Family` holds what the group shares, and bob can add, rename and delete inside it.
- `everyone` is listed for every account (JN-USR-020).

**Notes:**

- One folder per group, and membership alone decides who reaches it, so adding someone to a group gives them the
  folder and removing them takes it away (JN-USR-018).
- Move/Rename and Delete aren't offered on `groups` or on a group's own folder (JN-FB-037).

---

### JN-FB-036: Open what someone has shared with you

**Preconditions:** Signed in as `bob`, who is not an admin. `alice` has shared `Recipes` with him (JN-FB-027).

**Steps:**

1. Navigate to `/files` and tap **Shared with me**.
2. Have alice share a second folder, `Photos`, then reload and tap **Shared with me** again.

**Expected result:**

- **Shared with me** is offered only when something has been shared. Tapping it opens a **Shared with me** sheet
  listing what has been shared, one share or many, each reading "Shared by alice". Tapping an entry opens it.
- After step 2 the sheet lists both folders.
- bob's own files and his groups' folders aren't listed there: **My files** and **Groups** open those.

**Notes:**

- An admin is never offered the shortcut. They reach the same folders through **All files** (JN-FB-034).
- A share reads by the group that owns it when a group does, the same way.
- Only the top of each share is listed: a folder inside one already shared isn't listed again, and the trash is never
  listed.

---

### JN-FB-037: A home or a group's folder can't be deleted or moved

**Preconditions:** Signed in as `bob`, who is not an admin, has a home at `users/bob`, and is a member of `Family`.

**Steps:**

1. Open the context menu on `users`, on `users/bob`, on `groups` and on `groups/Family`.
2. Open a folder inside `users/bob` and open its context menu.
3. Sign in as an admin and repeat step 1.

**Expected result:**

- None of the four offers **Move/Rename** or **Delete** to bob.
- The folder in step 2 keeps the full menu: everything inside a home or a group folder is ordinary content.
- For the admin all four keep **Move/Rename** and **Delete**.
- The quark refuses the same delete, move or rename on its own, telling a member that a home folder, or a group's
  folder, can't be deleted or moved.

**Notes:**

- **Share…** stays offered on bob's own home, so he can share his own folder (JN-FB-027).
- A folder named `users` or `groups` on a USB drive is an ordinary folder; only the quark's own are protected.

---

### JN-FB-038: The users and groups folders can't be shared

**Preconditions:** Signed in as an admin.

**Steps:**

1. Open the context menu on `users`, then on `groups`.

**Expected result:**

- **Share…** is offered on neither, for an admin as much as for anyone else.
- The quark refuses such a share even when asked for it directly, answering that the users and groups folders can't be
  shared and to share a folder inside them instead.

**Notes:**

- Access adds up down the tree (JN-FB-030), so a share on `users` would hand over every home at once, and one on
  `groups` every group folder.

---

### JN-FB-039: Upload a file whose name is taken

**Preconditions:** The folder `Recipes` holds `soup.txt`, and the user can write there.

**Steps:**

1. Open `Recipes` and upload a file named `soup.txt` (JN-FB-006).
2. Tap **Keep both**.
3. Upload `soup.txt` again and tap **Replace**.
4. Upload `soup.txt` again and tap **Cancel**.
5. Upload several files at once, more than one of whose names is taken, tick **Do the same for the rest of this
   upload**, and answer once.

**Expected result:**

- A dialog titled **That name is taken** names the file and offers **Keep both**, **Replace** and **Cancel**. The
  quark never renames a file quietly.
- **Keep both** lands the new file beside the old one under the first free numbered name, `soup_(1).txt`.
- **Replace** overwrites what is there, and the file keeps the owner it already had, so re-uploading never hands
  ownership over (JN-FB-032).
- **Cancel** leaves both files alone and sends nothing for that one. The rest of the upload carries on, and it isn't
  counted as a failure.
- In step 5 the question is asked once and the answer stands for every later clash in that upload.

**Notes:**

- Both upload routes answer the same way: the single request that carries a small file, and the resumable session a
  large one uses.
- Clashes are asked about one at a time, so a batch that hits several doesn't stack dialogs.
- Importing from the Photos page never asks. Camera names like `IMG_0001.jpg` clash routinely and carry nothing the
  person chose, so an import always keeps both.

---

### JN-FB-040: Misspellings are underlined in a prose file

**Preconditions:** The app is running on iOS or Android. Files holds `notes.txt` containing `Teh meeting`, and
`config.json`.

**Steps:**

1. Open `notes.txt` in the plaintext editor (JN-FB-018).
2. Tap the underlined word.
3. Open `config.json` in the plaintext editor.

**Expected result:**

- `Teh` is underlined as a misspelling, and tapping it offers suggestions from the platform's spell checker.
- Nothing in `config.json` is underlined. Only prose files are checked: `.txt`, `.md`, `.markdown` and `.rst`,
  not code, `.log` or `.env`.
- On web and desktop nothing is underlined in either file, because those platforms give Flutter no spell
  checker. The Docs editor is not covered yet (#2210).
