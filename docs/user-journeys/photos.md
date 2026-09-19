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

- Upload progress is shown.
- After completion, the uploaded photo(s) appear in the Quark category.

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
- Renaming an album from its actions (**Rename**) follows the same rules. Changing only the case of its own name is
  allowed.

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
- On a narrow screen, where the sidebar sits above the grid, tapping a row scrolls the grid back into view.
- Tapping a photo opens the viewer over the album's photos only.
- Long-pressing a photo offers **Add to another album**, plus **Remove from album** (with a confirmation) in a user
  album or **Remove from favorites** in Favorites.
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
