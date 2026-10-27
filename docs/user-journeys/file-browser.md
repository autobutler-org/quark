# File Browser Journeys

Covers browsing, uploading, downloading, and managing files via the file browser at `/files`, including where
an office file and a Markdown file open (JN-FB-048, JN-FB-049).

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
- With more than one enabled storage device, an **Upload to device** sheet asks where the upload goes, starting on
  the default storage device (JN-SD-011), or with none set or enabled on the device chosen last time when it is
  still offered; dismissing it uploads nothing. A view filtered to one
  device uploads to that device without asking.
- A drive that is connected but not enabled is listed in that sheet as unavailable, with a note to mount it
  under System > Storage, and cannot be chosen. One such drive beside a single enabled device is enough for the
  sheet to open.
- If the storage devices cannot be listed, nothing is uploaded and a message says so.

---

### JN-FB-007: Upload a file via drag-and-drop (desktop/web)

**Preconditions:** User is on a platform that supports drag-and-drop.

**Steps:**

1. Navigate to `/files`.
2. Drag a file from the OS file manager onto the file browser drop zone.

**Expected result:**

- Drop zone highlights when file is hovered over it.
- File uploads on drop.
- With more than one enabled storage device, an **Upload to device** sheet asks where the upload goes, starting on
  the default storage device (JN-SD-011), or with none set or enabled on the device chosen last time when it is
  still offered; dismissing it uploads nothing. A view filtered to one
  device uploads to that device without asking.
- A drive that is connected but not enabled is listed in that sheet as unavailable, with a note to mount it
  under System > Storage, and cannot be chosen. One such drive beside a single enabled device is enough for the
  sheet to open.
- If the storage devices cannot be listed, nothing is uploaded and a message says so.
- File appears in the listing after upload completes.

---

### JN-FB-008: Download a file

**Preconditions:** At least one file exists in Files.

**Steps:**

1. Navigate to `/files`.
2. Open the file's menu: its three-dot button, a long press, or a right-click, which opens it at the pointer.
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
4. With more than one mounted storage device, optionally choose a **Destination device**; the picker starts on
   the device the item is on. The folder list shows that device's folders, and goes to its top level when it
   has no folder at the path being browsed.
5. Confirm.

**Expected result:**

- Item disappears from the source directory listing.
- Item appears in the destination directory, on the chosen device.
- The same folder on another device is a move; the same folder on the same device changes nothing.

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
3. Press the previous and next arrows, or the left and right arrow keys.

**Expected result:**

- Image viewer opens (`ImageViewerPage`) at `/view/<path>`.
- The opened photo is on screen before the folder listing returns. If that listing fails, the viewer stays on
  the one photo.
- The arrows then step through that folder's images by file name. They do not follow a custom column sort
  (JN-FB-044).
- Image is displayed correctly.
- User can navigate back to the file browser.

**Notes:** An archive preview (JN-FB-020) and the versions sheet (JN-FB-046) stay a single image.

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

**Preconditions:** A file of a type without a dedicated viewer (e.g. `.docx`, `.epub`) exists in Files.

**Steps:**

1. Tap the file.
2. Tap **Download**, or off web **Open with…**.

**Expected result:**

- The generic viewer opens at the file's `/view/<path>` URL, showing its name and type.
- **Download** saves the file to the device. **Open with…** hands it to the OS native handler.
- If no handler is available, a clear error or fallback message is shown.

**Notes:** A `.pdf` has its own viewer (JN-FB-045). A Markdown file opens rendered (JN-FB-049). Tapping an
Excel workbook in the listing asks to convert it (JN-SH-007); its `/view` URL is this page. A Word file
(JN-DOC-007), a PowerPoint file and an ODP (JN-SL-040) open here too.

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

When the connection to the Quark drops and comes back, the app sends itself a `resync`, since events published
while it was down are gone. The open listing refreshes at once, once, and takes any pending debounced refresh with
it, so what changed while the client was away shows without a manual refresh.

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
- With more than one enabled storage device, an **Upload to device** sheet asks where the upload goes, starting on
  the default storage device (JN-SD-011), or with none set or enabled on the device chosen last time when it is
  still offered; dismissing it uploads nothing. A view filtered to one
  device uploads to that device without asking.
- A drive that is connected but not enabled is listed in that sheet as unavailable, with a note to mount it
  under System > Storage, and cannot be chosen. One such drive beside a single enabled device is enough for the
  sheet to open.
- If the storage devices cannot be listed, nothing is uploaded and a message says so.
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

---

### JN-FB-041: A new owner is welcomed on Files

**Preconditions:** First-boot setup has just been finished with **Get started** (JN-AUTH-001), as `alice`.

**Steps:**

1. Read the welcome card.
2. Reload the app.
3. Open a folder, then go back to where Files opened.
4. Tap **Dismiss** on the card.
5. Reload the app.

**Expected result:**

- The card reads "Welcome, alice" and "Your files stay on your Quark. Start by adding something.", and offers
  **Upload**, **New folder** and **Open Vault**. Each does what the same action does elsewhere: the first two act on
  the folder on screen, and **Open Vault** goes to `/vault`.
- The card is still there after the reload: it stays until it is dismissed.
- It shows only where Files opens, not inside other folders or over search results, and at every width.
- Once dismissed it does not come back, on this device, for this Quark.

**Notes:**

- **Open Vault** is offered to every account, since each has a vault of its own (JN-VT-000).
- The card is owed from **Get started**. Leaving the wizard before that, by reloading on the recovery phrase or theme
  step, lands on Files without it.
- What is remembered is per device and per Quark, so another browser signed in to the same Quark shows no card.

---

### JN-FB-042: Signing in says welcome back

**Preconditions:** Quark is set up. Signed out.

**Steps:**

1. Sign in as `bob` (JN-AUTH-002).
2. Read the greeting.
3. Reload the app.

**Expected result:**

- One line reads "Welcome back, bob", with a **Dismiss** button and no other actions.
- After the reload there is no greeting: a session the app already held is not a sign-in.

**Notes:**

- A session old enough to have no stored username is greeted with "Welcome back" alone.
- An owner who has not dismissed their card (JN-FB-041) sees that card after signing in, not this line.

---

### JN-FB-043: Open, reload and share a file by its URL

**Preconditions:** A photo, an SVG, a video, an audio file and a `.pdf` exist in a folder in Files.

**Steps:**

1. From the folder, the home folder included, tap each file in turn.
2. Reload the page with the file open, or paste its URL into another signed-in browser.
3. Press browser back, then close a file with the viewer's back button instead.
4. Sign out, then open the file's URL.

**Expected result:**

- Each file opens at its own `/view/<path>` URL, a new history entry. `/files/<path>` to a file lands there too.
- A reload or a pasted URL reopens the same viewer.
- Browser back closes the viewer and returns to the folder.
- Closing the viewer returns to the folder, and browser back from there does not reopen the viewer.
- Signed out, the URL goes to sign-in, and signing in returns to the file.

**Notes:** Docs, sheets and text have their own `/docs`, `/sheets` and `/edit` URLs, and `/view/<path>` to one of
them goes there. Files inside an archive still open over the browser and have no URL of their own (#2328).

---

### JN-FB-044: Choose the columns the file list shows, and sort by them

**Preconditions:** User is at `/files` in list view (JN-FB-004), in a folder holding files and folders.

**Steps:**

1. Open the column picker: the **Columns** button beside the list/grid toggle on a wide screen, or the
   **Columns** section of the **Views** menu on a phone.
2. Check and uncheck **Kind**, **Modified**, **Device** and **Size**.
3. Tap a column's header, then tap it again.
4. Reload the page, or close and reopen the app.

**Expected result:**

- **Name** always shows. A fresh install also shows **Modified** and **Size**; **Kind** and **Device** start
  hidden.
- Each checked column appears at once as a header and a cell in every row, in the order Kind, Modified, Device,
  Size, and each unchecked one disappears. The picker stays open, so several can change in one visit.
- **Kind** names what a file is — Image, Video, Spreadsheet, Document, Folder — and **Modified** shows the date
  it last changed, such as `Oct 6, 2026`, in the viewer's time zone.
- A file the Quark sent no modification time for (some entries inside an archive) shows `--`, the same
  placeholder a folder's size shows.
- Tapping a header sorts by that column, and tapping it again reverses the order. Folders stay above files.
  Files that tie — the same kind, the same device — are ordered by name. A file with no modification time sorts
  as the oldest.
- The chosen columns are still the chosen columns after the reload or restart.

**Notes:**

- The choice is kept on the device, not on the Quark: another browser or phone starts from the default.
- The grid has no columns, so the picker is disabled there. The grid's sort row still offers Name, Kind,
  Modified, Size and Device. Per device (JN-FB-005) the listing is always a list, so the picker stays live.
- The trash and the folder picker do not offer the choice; they show Device and Size.
- A 360-pixel-wide phone has room for about two columns beside Name. More than that still fit without
  overflowing, but each one is cut short.

---

### JN-FB-045: Read a PDF in the app

**Preconditions:** A `.pdf` exists in a folder in Files.

**Steps:**

1. Tap the PDF, or open its `/view/<path>` URL directly.
2. Scroll through the pages, and zoom in and out.
3. Tap **Download** in the top bar, or off web **Open with…**.

**Expected result:**

- The PDF opens in the app at its `/view/<path>` URL (JN-FB-043) on web, iOS and Android, under a top bar
  naming the file. Nothing is downloaded to the device to read it.
- On web the browser's own PDF viewer shows it under that bar, with the browser's scrolling, zoom, page
  controls, search and printing.
- On iOS and Android the pages are a scrolling column that can be zoomed, with a thumb on the right edge that
  shows the page number and can be dragged. A loader shows until the first pages are ready, and a PDF that
  cannot be loaded shows a "Couldn't open the file" message in place of the pages.
- **Download** saves the file to the device. **Open with…** hands it to another app; it is not offered on web.

**Notes:**

- A browser with no PDF viewer of its own, as on most phones, gets the same pages-and-thumb viewer as the
  mobile apps. There it fetches the whole file before the first page appears; the apps fetch the parts they
  need as pages are shown.
- iOS no longer jumps straight to the system preview: the PDF opens in the app there too, and **Open with…**
  reaches the system one.
- The viewer needs no internet connection: the PDF engine ships inside the app, the web build included.
- A PDF inside an archive (JN-FB-020) still downloads; it has no viewer there.
- A Word file (JN-DOC-007), an ODP (JN-SL-040) and an EPUB still open in the generic viewer (JN-FB-019).
  Tapping an Excel workbook asks to convert it (JN-SH-007). A PowerPoint file opens here too, and its menu can
  import it (JN-SL-029). A Markdown file opens rendered (JN-FB-049).

---

### JN-FB-046: See a file's version history, preview a version and restore it

**Preconditions:** `notes.md` sits in a folder on the internal drive and has been saved at least twice, so the
Quark holds an earlier version of it.

**Steps:**

1. Open the file's menu, with its three-dot button or a long press on its row, and tap **Version history**.
2. Tap **Preview** on an earlier version.
3. Go back to the sheet and tap **Restore** on that version.
4. Read the confirmation and tap **Restore**.

**Expected result:**

- A sheet titled "Version history · notes.md" lists the versions newest first. Each row shows when the version
  was saved, its name or "Automatic", its size and who saved it: "You" for the signed-in account, a username
  for anyone else, "System" for one the Quark saved on its own.
- A loader shows only until the first listing arrives. The sheet's refresh button reloads the list with the
  rows still on screen.
- **Preview** opens that version read-only: a picture in the image viewer, an SVG in the SVG viewer, and a
  text, code or CSV file as plain text. Nothing in the preview can save over the file.
- The confirmation says the file goes back to that version and that what it holds now is saved first as
  "Before restore", so the restore can be undone.
- After **Restore** the sheet says "Restored", the list reloads with a "Before restore" version at the top,
  and the file in Files holds the restored content. **Cancel** changes nothing.
- While a restore or a preview is loading, that row shows a loader and every other row's buttons are dimmed.

**Notes:**

- **Version history** is offered on files on the internal drive only: not on a folder, a file on a USB drive,
  an entry inside an archive (JN-FB-020), or anything in the trash.
- A kind with no read-only viewer here, such as a video, a PDF or a document, says "A preview isn't available
  for this kind of file." A version over 25 MB says it is too large to preview. Either can still be restored.
- A refusal shows as a sentence in the sheet, where a snack bar would be hidden: restoring into a folder the
  account can only read, for one.
- Comparing two versions, retention settings and the space versions use are not built yet (#2992).

---

### JN-FB-047: Resume a video where you left off, and mark it watched

**Preconditions:** A video several minutes long exists in Files. The account has not played it before.

**Steps:**

1. Open the video (JN-FB-016), let it play for a minute or so, and go back to Files.
2. Open the same video again.
3. Play or seek to the last few seconds, pause, and go back.
4. Open the video a third time, open **More options** and tap **Mark as unwatched**.
5. Open **More options** again and tap **Mark as watched**.

**Expected result:**

- The second time, the video opens at the position it was left at instead of the start.
- A video left in its last 5% counts as watched: the third time it opens from the start, and **More options**
  offers **Mark as unwatched**.
- **Mark as unwatched** forgets both the watched state and the saved position, and the menu then offers **Mark
  as watched**. **Mark as watched** sets it back, and the video opens from the start next time.
- The position and the watched state belong to the signed-in account. Another account opening the same video
  starts from the beginning with it unwatched.

**Notes:**

- The position is saved every few seconds while the video plays, when it is paused and when the viewer closes.
  A save that fails is silent and never interrupts playback; a failed **Mark as watched** or **Mark as
  unwatched** shows a snack bar.
- The Quark stores the state against the file's path, with `GET` and `PUT /api/v0/playback` and
  `PUT /api/v0/playback/watched`. Moving or renaming the video starts it over.
- A watched video stays watched while it is played again, until **Mark as unwatched**.
- A "Continue watching" row, a theater library, subtitles and chapters are not built yet (#2985).

---

### JN-FB-048: Where a Word file, a workbook, a PowerPoint file or an ODP opens

**Preconditions:** Signed in. One folder holds `q1.docx`, `budget.xlsx`, `Talk.pptx` and `Talk.odp`.

**Steps:**

1. Tap `q1.docx`, then go back.
2. Tap `budget.xlsx` and cancel the convert dialog.
3. Tap `Talk.pptx`, go back, and open its menu.
4. Tap `Talk.odp`, go back, and open its menu.

**Expected result:**

- `q1.docx` opens the generic viewer. The document is not rendered, and Docs does not list it (JN-DOC-007).
  A `.docm`, `.odt` or `.rtf` does the same.
- `budget.xlsx` asks **Convert to .qsheet?** and does not open a sheet viewer. **Cancel** leaves it unopened.
  Confirming writes a sibling `.qsheet` and opens that in the editor (JN-SH-007). An `.ods` or `.xls` skips the
  question and opens the generic viewer.
- `Talk.pptx` opens the generic viewer. Its menu offers **Open as presentation**, which imports a `.qslide`
  and opens the editor (JN-SL-029). The slides are not drawn from the `.pptx` itself.
- `Talk.odp` opens the generic viewer. Its menu has no **Open as presentation**, and Slides does not list it
  (JN-SL-040).
- None of the four is drawn in the app on tap. A PDF is (JN-FB-045), and a Markdown file is (JN-FB-049).

**Notes:**

- The Quark can preview a word-processing file, a presentation (including `.odp`) and a workbook, and can
  convert or import them to `.qdoc`, `.qslide` and `.qsheet`. The app uses that only for the PowerPoint menu
  import and for the `.xlsx` / `.xlsm` convert prompt.
- Inside an archive, all four download instead of opening (JN-FB-020).

---

### JN-FB-049: Read a Markdown file

**Preconditions:** `notes/readme.md` exists. It has a heading, a relative link to another file in `notes/`, and
a remote image.

**Steps:**

1. Tap the file, or open `/markdown/notes/readme.md`.
2. Tap **Source**, then **Rendered**.
3. Tap the relative link, then go back.
4. Tap **Load remote image** on the remote image.
5. Tap **Edit**.

**Expected result:**

- The file opens at `/markdown/notes/readme.md`, named in the bar. Headings, lists, tables and code blocks are
  drawn. The page is not an editor.
- **Source** shows the file's text. **Rendered** returns to the drawn page.
- A relative link opens that file. A link cannot climb above the files root. An `http` or `https` link opens
  outside the app. Any other scheme, including `javascript:` and `data:`, does nothing.
- A picture in the same folder loads on its own. A remote picture stays a button until **Load remote image**
  (or **Load remote image:** and its alt text).
- **Edit** opens the plaintext editor. Back from there returns to this page.
- A file the rendered view stops early on says how much it showed, for example "Showing the first 1.0 MB of
  2.0 MB. View the source to read the rest." **Edit** stays off then. **Source** still pages through the rest.
- A failure reads "Couldn't load the file." When the Quark cannot be reached, the disconnected state shows,
  with a retry.

**Notes:**

- `.markdown` opens here too. A `.txt` opens at `/code/<path>` instead, and **Edit** there reaches the
  plaintext editor.
- The rendered view reads at most 1 MB. Raw HTML is shown as text. An SVG image in the file is drawn; a
  script inside that SVG does not run.
- The source chip's key is `markdown_viewer_source_toggle`, **Edit** is `markdown_viewer_edit`, and a remote
  image's button starts with `markdown_viewer_load_image_`.
- An `.md` inside an archive is previewed as text, not rendered (JN-FB-020).
