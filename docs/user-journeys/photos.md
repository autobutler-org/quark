# Photos Journeys

Covers the Photos page (`/photos`), including Quark photos, mobile device photos, albums, and favorites.

---

### JN-PH-001: Browse Quark photos

**Preconditions:** Image files exist on the Quark device.

**Steps:**

1. Navigate to `/photos`.
2. Ensure the **Quark** or **All** category tab is selected.

**Expected result:**

- Thumbnail grid of images stored on the quark is displayed.
- Images load with correct thumbnails.
- The pictures a PowerPoint import copied out of a presentation (JN-SL-028), in the `Talk_media` folder beside
  `Talk.qslide` or a numbered `Talk_(1).qslide`, are not listed: they stay in Files and in the presentation. Moving or
  renaming the `.qslide` away from that folder lists them again.

---

### JN-PH-002: Browse mobile device photos (mobile only)

**Preconditions:** Running on mobile (iOS or Android). Photo library permission is granted.

**Steps:**

1. Navigate to `/photos`.
2. Select the **Mobile** category tab.

**Expected result:**

- Thumbnails from the device photo library appear.
- Permission prompt appears if permission has not yet been granted; granting it shows photos.

---

### JN-PH-003: Open a photo in the image viewer

**Preconditions:** Photos are visible in the grid (JN-PH-001).

**Steps:**

1. Tap a photo thumbnail.

**Expected result:**

- Full-resolution image opens in the image viewer.
- User can pan and zoom.
- Navigating back returns to the photos grid.

---

### JN-PH-004: Paginate through Quark photos

**Preconditions:** More than one page of Quark photos exists (> page size, default 50).

**Steps:**

1. Navigate to `/photos`.
2. Scroll to the bottom of the grid.

**Expected result:**

- Additional photos load automatically (infinite scroll / pagination).
- No duplicate items appear.

---

### JN-PH-005: Adjust grid column count

**Preconditions:** User is on the Photos page.

**Steps:**

1. Use the column-count slider or pinch-to-zoom gesture to increase/decrease columns.

**Expected result:**

- Grid reflows with the new column count (min 1, max 8).
- Thumbnails resize proportionally.

---

### JN-PH-006: Upload a photo from the device

**Preconditions:** Running on mobile with photo library permission granted.

**Steps:**

1. Navigate to `/photos`.
2. Tap the upload/FAB button.
3. Select one or more photos from the device library.

**Expected result:**

- With more than one enabled storage device, an **Upload to device** sheet asks where the photos go, starting on
  the default storage device (JN-SD-011), or with none set or enabled on the device chosen last time (in Files or
  Photos) when it is still offered; dismissing it uploads nothing.
- A drive that is connected but not enabled is listed in that sheet as unavailable, with a note to mount it
  under System > Storage, and cannot be chosen. One such drive beside a single enabled device is enough for the
  sheet to open.
- If the storage devices cannot be listed, nothing is uploaded and a message says so.
- Upload progress is shown.
- After completion, the uploaded photo(s) appear in the Quark category. They land in the top level of the chosen
  device.

---

### JN-PH-007: Mark a photo as a favorite

**Preconditions:** At least one photo is visible in the grid.

**Steps:**

1. Long-press a photo (or open its context menu).
2. Select **Favorite** (or tap the heart icon).

**Expected result:**

- Photo is added to your own Favorites category.
- Favorite indicator (heart icon) is visible on the thumbnail.
- Favorites belong to each account. Another account, an admin included, does not see your favorite and can favorite
  the same photo independently.

---

### JN-PH-008: View favorites

**Preconditions:** At least one photo has been favorited (JN-PH-007).

**Steps:**

1. Navigate to `/photos`.
2. Select the **Favorites** category tab.

**Expected result:**

- Only the photos you favorited are shown, not another account's favorites.
- Non-favorited photos are not visible.
- Each account has its own Favorites album, created the first time it is needed.

---

### JN-PH-009: Remove a photo from favorites

**Preconditions:** At least one photo is favorited (JN-PH-007).

**Steps:**

1. Navigate to `/photos` → Favorites.
2. Long-press the favorited photo (or open context menu).
3. Select **Remove from favorites**.

**Expected result:**

- Photo is removed from your Favorites listing. Another account that favorited it keeps its favorite.
- It still appears under its original category (Quark / Mobile / All).

---

### JN-PH-010: Create an album

**Preconditions:** User is on the Photos page.

**Steps:**

1. Open the album sidebar.
2. Tap **New album**.
3. Enter an album name.
4. Confirm.

**Expected result:**

- New album appears in the sidebar.
- Album is initially empty.
- Albums belong to the account that created them. Only you see your albums, an admin included; deleting an account
  deletes its albums but not the photos in them.
- Album names are unique within their folder among your own albums, ignoring case, and cannot contain `/`. Another
  account can have its own `Trips`. Top-level albums share one
  folder with Favorites and Inbox. A name already taken there (`trips` next to `Trips`) or containing `/` cannot be
  saved: the dialog says why ("There's already an album with that name here." or "Album names can't contain a
  slash.") and **Save** stays disabled.
- If the Quark still refuses the name, because another device took it first, a snack bar shows the same message and
  the sidebar is unchanged.
- Renaming an album from its actions (**Rename**) follows the same rules. The actions open from the album's menu
  button in the sidebar, a right-click, or a long press; Favorites and Inbox have none. Changing only the case of its
  own name is allowed.

---

### JN-PH-011: Add photos to an album

**Preconditions:** You own a user album (JN-PH-010). Photos are visible.

**Steps:**

1. Open the album from the sidebar (JN-PH-012).
2. Tap **Add Photos** in the app bar. The grid switches to All photos in "adding to album" mode, with the album
   named in the header.
3. Select one or more photos from the grid.
4. Confirm the selection.

**Expected result:**

- Selected photos are associated with the album. Another account's albums are never offered.
- The grid returns to the album, now showing the added photos, and the sidebar shows its new count.
- While picking, the photos the album already holds show checked and cannot be picked again.
- Adding a photo the album already holds changes nothing and says "Already in "<name>"", never "1 photo added".
- Canceling the selection (or pressing Escape) also returns to the album, with nothing added.
- System albums (Favorites, Inbox) show no **Add Photos** action.
- Photos can also be added from plain selection mode: **Select**, pick photos, then **Add to album** in the bottom bar.

---

### JN-PH-012: View an album

**Preconditions:** You own an album with at least one photo (JN-PH-011).

**Steps:**

1. Open the album sidebar.
2. Tap an album.
3. Tap **All photos**, the first row of the album list.

**Expected result:**

- The album opens in place: the user stays on the Photos page, the grid shows only the album's photos, and the
  album's row is highlighted. The column slider, sidebar, and app bar stay put; the "Showing" categories hide while
  an album is showing.
- The URL names the album: `/photos?album=Trips` for a top-level album, `/photos?album=Trips/Japan` for one nested
  inside it. Reloading or sharing it lands on the same album.
- Links by album id (`/photos?album=12`) and names in a different case (`/photos?album=trips`) open the album too, and
  the URL is rewritten to the album's name. A name wins over an id, so an album named `2024` opens before the album
  whose id is 2024.
- Album names are unique within their folder, ignoring case, and cannot contain `/` (JN-PH-010), so the URL is a
  name path. Only an album from before that rule, one that shares its path with another or has `/` in its name, is
  linked by its id instead. An unknown name or id shows All photos at `/photos`, and so does another account's album
  id.
- Renaming the showing album updates the URL to its new name; deleting it returns to All photos.
- On a narrow screen, where the sidebar sits above the grid, tapping a row scrolls the grid back into view once the
  album's photos have loaded: one movement that stops at the top of the grid, or at the end of an album too short
  to fill the screen, with no overshoot or bounce. Under reduced motion it is a jump.
- Tapping a photo opens the viewer over the album's photos only.
- Each photo has a menu button; it opens, like a long press or a right-click on the photo, at the pointer. The menu
  offers **Add to another album**, plus **Remove from album** (with a confirmation) in a user album or **Remove from
  favorites** in Favorites.
- An empty album says so: "Star a photo to add it here." for Favorites, and "Add photos to "<name>" from All
  photos." for a user album. An unreachable quark shows the disconnected view instead.
- Tapping **All photos** returns the grid to the library, in the category that was showing before, at `/photos`.
- The album chips in the photo viewer's metadata panel open the album the same way.

---

### JN-PH-013: View photo metadata

**Preconditions:** A Quark photo is open in the image viewer.

**Steps:**

1. Open the info panel or tap the info icon.

**Expected result:**

- Metadata is shown: filename, date, dimensions, size, etc.

---

### JN-PH-014: Rotate a Quark photo

**Preconditions:** A Quark photo is open.

**Steps:**

1. Open the rotate action (toolbar or context menu).
2. Tap rotate left or rotate right.

**Expected result:**

- Photo is rotated and the change is persisted on the quark.
- Thumbnail in the grid reflects the new orientation.

---

### JN-PH-015: Copy a Quark photo

**Preconditions:** A Quark photo exists.

**Steps:**

1. Open context menu on the photo.
2. Select **Copy**.
3. Choose a destination folder.

**Expected result:**

- A copy of the photo appears in the destination.
- Original is unchanged.

---

### JN-PH-016: Share a photo

**Preconditions:** A Quark photo is in a folder the user owns, or the user is an admin.

**Steps:**

1. Open the photo in the image viewer.
2. Open the more menu and select **Share…**.
3. Pick an account or group, choose a level, and tap **Share**.

**Expected result:**

- The share sheet opens for that photo, the same as **Share…** in Files (JN-FB-027).
- The account or group can open the photo.

**Notes:**

- A photo from the device, rather than the Quark, has no **Share…**.
- Albums can't be shared; share the folder that holds the photos instead.

---

### JN-PH-017: Upload photos via drag-and-drop (web)

**Preconditions:** Running Quark in a web browser.

**Steps:**

1. Navigate to `/photos`.
2. Drag one or more photos, or a folder of them, from the OS file manager onto the page.

**Expected result:**

- The page highlights while the drag is over it.
- The photos upload on drop the same way as the upload button (JN-PH-006) — the same device choice with more
  than one device enabled, and the same stop when the devices cannot be listed — and appear in the grid.
- A dropped file that is not a photo is left out, and a message says how many were not uploaded. A drop with
  no photos in it uploads nothing and shows only that message.

**Notes:**

- Photos are recognized by extension, raw camera formats included. SVG and video files are not photos here.

---

### JN-PH-018: Change the sort order

**Preconditions:** Photos are visible in the grid (JN-PH-001), an album (JN-PH-012), or a category tab.

**Steps:**

1. Tap the sort button in the app bar.
2. Choose **Taken, newest first**, **Taken, oldest first**, **Added, newest first**, **Added, oldest first**,
   **Name (A-Z)**, or **Name (Z-A)**.

**Expected result:**

- The grid reloads in the chosen order: All photos, every category tab (Quark, Mobile, Favorites), and every
  album view.
- The choice is remembered across navigation and app restart, defaulting to **Taken, newest first** the first
  time.
- **Taken** goes by the capture date in the photo's EXIF data. A photo with none, or one the Quark has not read
  yet, goes by its date added instead. The Quark reads a photo's date the first time its thumbnail is made, and
  reads the rest of the library when it starts.
- **Added** goes by when the file arrived on the Quark, or, in an album, when the photo joined the album.
- A device photo has no filename to sort by, so a Mobile-tab name sort leaves those photos in the device's own
  order. Both date sorts order device photos by when the device took or saved them.

---

### JN-PH-019: Change the album sort order

**Preconditions:** The album sidebar lists at least one user album (JN-PH-010).

**Steps:**

1. Tap the sort button beside **New album** in the sidebar's **Albums** header.
2. Choose **A–Z**, **Z–A**, **Newest**, or **Oldest**.

**Expected result:**

- The user's albums reorder at once, sub-albums included, without reloading. Newest and Oldest go by when the
  album was created; names ignore case.
- The system albums (Favorites and the inbox) stay at the top in every order.
- The choice is remembered across navigation and app restart, defaulting to **A–Z** the first time.

---

### JN-PH-020: Browse photos by month

**Preconditions:** Photos are visible in the grid (JN-PH-001), an album (JN-PH-012), or a category tab, sorted
by date (JN-PH-018).

**Steps:**

1. Scroll through the grid.

**Expected result:**

- Photos sit under month headers such as **March 2025**, in the grid's sort order, headed by the date that sort
  goes by: a photo taken in 2019 and uploaded today is under its 2019 month when sorted by date taken, and under
  this month when sorted by date added. The header of the month in
  view stays pinned to the top of the grid until the next month's header pushes it out.
- While the grid scrolls, a label naming the month in view floats at the right edge of the grid, and fades
  out about a second and a half after scrolling stops. Scrolling the album sidebar does not show it.
- In an album sorted by date added, a photo is filed under the month it was added to the album. A photo with no
  date sits under **Unknown date**.
- Under a name sort there are no headers.
- The **All** tab lists Quark photos before device photos, so a month can appear once for each.

---

### JN-PH-021: Act on a library photo from its menu

**Preconditions:** Quark photos are visible under All photos (JN-PH-001), outside any album, and Demo mode is off.

**Steps:**

1. Tap a photo's menu button, or right-click the photo.
2. Choose **Add to album**, **Favorite** (or **Unfavorite**), **Download**, **Share…**, **Make a copy**, or
   **Delete**.

**Expected result:**

- The menu opens at the pointer, or under the button, and the action runs as it does from the image viewer's
  More options. **Make a copy** and **Delete** reload the grid; **Delete** asks first and moves the photo to the
  trash.
- A long press on the photo still starts selecting, as before. A device photo has no menu, since there is nothing on
  the Quark to act on.

---

### JN-PH-022: Clear out duplicate photos

**Preconditions:** Demo mode is off, and the library holds copies of the same photo. Quark hashes a photo when it
renders or receives its thumbnail, and hashes the rest of the library in the background each time it starts, so a copy
added outside Quark shows up once its thumbnail loads or after the next restart.

**Steps:**

1. On All photos, tap **Duplicates** in the app bar (`/photos/duplicates`).
2. Tap a copy to switch it between **Keep** and **Delete**, or tap **Select suggested** to mark every identical copy
   but one.
3. Optionally, when a picture is saved in more than one format, pick a format from **Keep: Any** in the app bar.
4. Tap **Delete N photos**, check the copies the confirmation lists, and confirm.

**Expected result:**

- Photos are grouped as **Identical copies** (the same file) or **Similar photos** (alike, but maybe edited or
  resized). Each copy shows its name and folder, and its drive when it is not on the internal one.
- A very flat photo (an overcast sky, a snowfield, fog) is never offered as a similar photo: it is grouped only with
  byte-identical copies, because different flat photos look alike to the comparison. Until the background pass has
  read a photo again after an update, it counts as flat too.
- Every copy starts marked **Keep**, and no delete bar shows until a copy is marked **Delete**. **Select suggested**
  marks every copy but one in each identical group and never touches similar photos; it is offered while an identical
  group still has a spare copy unmarked. A group always keeps at least one copy.
- While copies are marked, the bar at the bottom counts them and the groups they are in (**5 copies in 4 groups**), so
  marks scrolled out of view are still counted, and **Clear** clears every mark. The confirmation names every marked
  copy with its folder.
- The page refreshes itself now and then without losing the marks; a group that appears for the first time starts
  with none marked.
- Every copy's thumbnail loads, in identical and similar groups alike: one the Quark refused while busy is asked for
  again, and one it lacks is rendered on this device where it can be.
- **Keep: Any** appears only when a similar group is one picture saved in several formats: every copy is a
  different format (`IMG_1.HEIC` and an exported `IMG_1.jpg`), and their perceptual hashes are all within a few bits
  of each other. Names play no part, so a renamed export still counts and two shots that merely share a name do not.
  Picking a format marks the other formats' copies in each such group that has one, and leaves identical and other
  similar groups alone. Picking **Any** clears those marks. The choice lasts until you leave the page, applies to
  groups that appear later, and a copy tapped afterwards stays as tapped until the choice changes.
- Confirming moves the marked copies to the trash and reloads the groups. A copy that could not be deleted is named
  in a snack bar by count.
- A photo appears in one group at most, and a photo that was deleted, moved or trashed stops appearing.
- An admin sees the library index above the groups (#3556). While the background pass is running, paused, or has
  not reached every photo, it reads **Still indexing, so results may be incomplete** (or **Indexing paused, ...**),
  with how many photos have been checked for duplicates out of the library and how many dates have been read. Once
  every photo is indexed it reads **All N photos indexed** with when the last pass finished. **Pause indexing** holds
  the pass after the photo it is reading, and **Resume indexing** carries on from there; a restart of the Quark
  forgets a pause. When photos could not be read, **N photos couldn't be read** lists each by name and folder with a
  plain reason: it can't be read as a photo, it is a camera RAW photo and this Quark can't convert RAW files, it is
  too large to check, or it couldn't be opened. The status updates as the pass moves, without a refresh.
- Anyone who is not an admin sees no index status: the Quark tells only admins whether indexing is done, so an empty
  page for them may still mean "not indexed yet".

---

### JN-PH-023: Search photos by file name

**Preconditions:** Photos are visible in the grid (JN-PH-001), an album (JN-PH-012), or a category tab.

**Steps:**

1. Tap **Search** (the magnifying glass) in the app bar. A search field opens under the bar, ready to type in.
2. Type part of a file name.
3. Tap the **✕** at the end of the field, or press Escape, to leave the search.

**Expected result:**

- The grid narrows as you type to the photos whose file name contains the text, ignoring case. What is already
  loaded narrows at once; a moment after typing pauses, the Quark answers with the first page of matches, and
  scrolling loads the next pages until every match is shown.
- The search applies to whatever the grid shows: All photos, a category tab, or the album that is open. An album
  and the Mobile tab are filtered on the device, since everything in them is already loaded.
- The matches keep the chosen sort order (JN-PH-018). The Quark orders them, including by capture date under
  **Taken**. Changing the sort asks for the matches again in that order.
- When nothing matches, the grid reads **No photos match "…"**. When the Quark cannot be asked, it says the search
  could not be done instead of claiming nothing matches.
- Leaving the search brings the whole grid back.

**Notes:**

- Only file names are searched. Searching by capture date, camera or other metadata is deferred (#2059).
- GET /photos takes `q`, a file name substring, and pages every match: each page's total is the match count.
  The app follows those pages, so a search is not cut off at 500 (#3523).
- A device photo is matched by its title, which iOS does not always report.
- Demo mode searches the sample library on the device.

---

### JN-PH-024: Photos stay current without a refresh

**Preconditions:** Photos is open on a Quark connection (JN-PH-001), and a second client can reach the same Quark.

**Steps:**

1. From the second client, upload a photo, or delete or move one.
2. Watch the grid.
3. Lose the connection to the Quark (switch the device offline), change a photo from the second client, then
   reconnect.

**Expected result:**

- After step 1 the grid reloads itself with the change, without a manual refresh. A sharing change reloads it too.
- After step 3 the grid reloads once the connection is back, so the change made while it was down shows.

**Notes:**

- The page's own upload reloads the grid once it finishes, not on each file's event.
- A reconnect reaches the page as a `resync` event the app sends itself, the same one the Quark sends when it
  dropped events a slow client missed.

---

### JN-PH-025: Collapse the albums list

**Preconditions:** Photos is open (JN-PH-001).

**Steps:**

1. Tap **Albums**, the heading with a chevron at the top of the album sidebar.
2. Tap it again.

**Expected result:**

- After step 1 the whole list folds away under its header: All photos, Favorites and the inbox, and every album.
  On a narrow screen the grid moves up into the space; the wide layout's sidebar keeps its width.
- After step 2 the list is back as it was: the same album highlighted, the same sub-albums open, in the same order.
- The grid shows the same photos throughout, and stays at a position its content can hold, with no bounce.
- The sort button and **New album** stay in the header and work while the list is folded; neither folds or opens it.
- The list starts open, and stays folded through an album pick, a sort, and a refresh for as long as Photos is open.

**Notes:**

- The heading is a button: it takes keyboard focus, answers Enter and Space, and a screen reader announces it as
  expanded or collapsed. Folded rows cannot be reached by Tab or a screen reader.
- Under reduced motion the chevron changes without turning.

---

### JN-PH-026: Show an album as a slideshow on a dedicated screen

**Preconditions:** An account with at least one album that has photos (JN-PH-012). A screen with a browser, such as a
photo frame or a tablet, on the same network as the Quark.

**Steps:**

1. On the screen, open `/frame` on the Quark's address, for example `http://quark.local:8080/frame`.
2. Sign in with your username and password. This takes about ten seconds on a small screen.
3. Tap an album, such as **Favorites**.
4. Tap the picture to open the menu, then **Albums** to pick another.

**Expected result:**

- After step 2 the page lists your own albums with their photo counts, and nobody else's.
- After step 3 the screen goes fullscreen where the browser allows it and shows the album's photos in a random
  order, a new one about every fifteen seconds, fading from one to the next. A photo is shown whole, never cropped.
- The next time `/frame` opens, it starts the album you last picked without asking. The sign-in lasts as long as an
  app sign-in does (30 days, renewed as the screen uses it).
- Photos that are HEIC or RAW are shown as JPEG. Videos and other files in the album are skipped.
- If the Quark cannot be reached, the screen keeps the picture it has, says so at the bottom, and tries again every
  thirty seconds. If the sign-in has ended, the screen goes back to the sign-in form.
- The menu has **Albums**, **Full screen**, **Sign out** and **Close**, and closes itself after ten seconds.

**Notes:**

- `/frame?album=<id>` plays one album, `&interval=<seconds>` changes the pace, and `&order=newest` or
  `&order=oldest` plays in date order instead of shuffling.
- The page is plain HTML, CSS and JavaScript with no framework, about 22 KB, so it runs on a screen too weak for the
  app's web client. It uses the signed-in account, so what it can show is what that account can read.
- Under reduced motion the photos change without fading.
