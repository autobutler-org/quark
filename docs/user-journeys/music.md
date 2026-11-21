# Music Journeys

Covers the Music page (`/music/<tab>`): the songs, albums, artists and genres the Quark found in the audio files
the user can read, search over their tags, and the album and artist pages (#3283). The library is built by a scan
of every drive; see [`docs/architecture/music-library.md`](../architecture/music-library.md).

---

### JN-MU-001: Browse songs

**Preconditions:** User is logged in. The Quark has scanned at least one audio file the user can read.

**Steps:**

1. Open the drawer and tap **Music**, beside **Photos**, or navigate to `/music`.

**Expected result:**

- The app lands on `/music/songs`, the **Songs** tab, with **Albums**, **Artists** and **Genres** beside it.
- Each song shows its cover (or a disc placeholder), its title, its artist and album, and its length.
- The app bar's refresh button, beside the brand button, fetches the library again. On a phone, where the bar has
  no refresh button, pulling the list down does.

**Notes:** The list is `GET /api/v0/music/tracks`, every page of it, in album order. Each tab has its own URL
(`/music/songs`, `/music/albums`, `/music/artists`, `/music/genres`), so reload and Back keep the tab. Rows are
keyed `music_track_<path>`.

---

### JN-MU-002: Play a song

**Preconditions:** JN-MU-001 passes.

**Steps:**

1. On any Music list, tap a song.
2. Close the player with its back button.

**Expected result:**

- The song opens in the audio player at its `/view/<path>` URL (JN-FB-043), on the drive it is on.
- Closing the player returns to the Music page it was opened from.

**Notes:** The viewer's URL carries `?from=` the Music URL, and `?serial=` for a song on an attached drive. A queue,
shuffle and gapless playback are #2983.

---

### JN-MU-003: Open an album

**Preconditions:** JN-MU-001 passes.

**Steps:**

1. Tap the **Albums** tab.
2. Tap an album.
3. Tap the back arrow in the app bar.

**Expected result:**

- Albums show as a grid of cards: the cover, the title, the album artist and year, and the track count.
- Step 2 opens `/music/albums/<albumKey>`, titled with the album, listing its songs in disc and track order.
- Step 3 returns to `/music/albums`.

**Notes:** The album URL deep-links: pasting it or reloading opens the same album. Cards are keyed
`music_album_<albumKey>`, the back arrow `music_back`.

---

### JN-MU-004: Open an artist

**Preconditions:** JN-MU-001 passes.

**Steps:**

1. Tap the **Artists** tab.
2. Tap an artist.
3. Tap **Songs** on the artist's page.

**Expected result:**

- Each artist row shows how many albums and songs credit them.
- Step 2 opens `/music/artists/<name>`, titled with the artist, on an **Albums** tab of their albums. Tapping one
  opens it as in JN-MU-003.
- Step 3 lists the artist's songs.

**Notes:** Artists are album artists: a song with no album artist tag is credited to its track artist. Rows are
keyed `music_artist_<name>`.

---

### JN-MU-005: Filter songs by genre

**Preconditions:** JN-MU-001 passes, with songs in at least two genres.

**Steps:**

1. Tap the **Genres** tab.
2. Tap a genre.
3. Tap the clear button on the **Genre:** chip.

**Expected result:**

- Each genre row shows how many songs carry it.
- Step 2 moves to `/music/songs`, showing only that genre's songs under a **Genre: <name>** chip.
- Step 3 lists every song again.

**Notes:** Rows are keyed `music_genre_<name>`; the chip `music_genre_filter`, its clear button
`music_genre_filter_clear`.

---

### JN-MU-006: Search music

**Preconditions:** JN-MU-001 passes.

**Steps:**

1. Type a word from a title, artist, album or genre into the search field above the tabs.
2. Tap a result.
3. Clear the field.

**Expected result:**

- Once typing pauses, the matching songs replace the tabs, best match first, each with the tag that matched under
  it. Nothing matching says "No matches".
- Step 2 plays the song as in JN-MU-002.
- Step 3 brings the tabs back.
- On a Quark whose database is PostgreSQL, the results read "Your Quark doesn't support that yet." (#2958).

**Notes:** `GET /api/v0/music/search`, which answers 501 on PostgreSQL. The field is keyed `music_search`.

---

### JN-MU-007: An empty or scanning library

**Preconditions:** User is logged in. The Quark has no audio files the user can read, or is scanning.

**Steps:**

1. Navigate to `/music`.

**Expected result:**

- While a scan is under way the page reads "Scanning your music"; otherwise "No music yet", with "Add audio files
  to your Quark, then scan the library." under it.
- An admin also gets a **Scan music** button, which queues a scan (JN-MU-008) and shows the scanning state.
- When the scan finishes and finds music, the page lists it without a refresh (JN-MU-009).

**Notes:** `GET /api/v0/music/status`: `trackCount` 0 is the empty state, and a `scanJobId` means scanning. The
button is keyed `music_scan`.

---

### JN-MU-008: Rescan the music library (admin)

**Preconditions:** User is logged in as an admin.

**Steps:**

1. Navigate to `/settings/updates`.
2. Under **Maintenance**, in **Music library**, tap **Rescan music library**.

**Expected result:**

- The card reads "Scan queued. Its progress shows in Jobs." and the jobs badge shows the scan running.
- A member has no Maintenance group and no rescan.

**Notes:** `POST /api/v0/music/rescan` (admin only), which answers 202 with the queued job. The button is keyed
`rescan_music_button`, the line under it `rescan_music_status`.

---

### JN-MU-009: The page follows the library

**Preconditions:** JN-MU-001 passes, with the Music page open.

**Steps:**

1. In another window, upload an audio file to Files, or delete one.

**Expected result:**

- Once the Quark has read the file, the Music page lists it (or drops it) without a refresh.

**Notes:** The Quark publishes `music_library_changed`, debounced, when the library changes; the page fetches
again on it, and on a `resync` after its socket reconnects.
