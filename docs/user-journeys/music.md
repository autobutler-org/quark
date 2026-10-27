# Music Journeys

Covers the Music page (`/music`): the library the Quark builds from the audio files it holds, browsed as Songs,
Albums, Artists and Genres, searched by tag, and played in the file viewer's audio player (#2982, #3283). The design
is [`docs/architecture/music-library.md`](../architecture/music-library.md).

---

### JN-MU-001: Browse songs

**Preconditions:** User is logged in. At least one audio file (mp3, flac, ogg/opus, m4a/aac, wav or wma) exists in
Files, and the library has been scanned.

**Steps:**

1. Open the drawer and tap **Music**, or navigate to `/music`.

**Expected result:**

- The address bar moves to `/music/songs`, and the Songs tab lists every song the user can read, by title.
- Each row shows the cover (a disc when the track has none), the title, the artist and album, and the duration.
- With more than 200 songs, **Show more** at the bottom of the list adds the next page.
- The app bar's refresh button, beside the brand button, fetches the library again.

**Notes:** A song the user cannot read is never listed. Rows are keyed `music_track_<path>`. An untagged song is
listed under its file name.

---

### JN-MU-002: Play a song

**Preconditions:** JN-MU-001 passes.

**Steps:**

1. On any Music tab, album page or artist page, tap a song.
2. Close the player with its back button.

**Expected result:**

- The song opens at its `/view/<path>` URL in the audio player, and plays.
- Closing the player returns to the Music page, album or artist the song was opened from.

**Notes:** The viewer's URL carries `?from=` with the Music location, as Books does (JN-BK-002). A queue, shuffle and
play history are later work (#2983).

---

### JN-MU-003: Switch tabs

**Preconditions:** JN-MU-001 passes.

**Steps:**

1. On `/music/songs`, tap **Albums**, then **Artists**, then **Genres**.
2. Reload the page.

**Expected result:**

- Each tab has its own URL: `/music/albums`, `/music/artists`, `/music/genres`.
- Albums is a grid of covers with title, artist, year and track count; Artists lists each album artist with album and
  track counts; Genres lists each genre with its track count.
- A reload lands on the same tab. An unknown tab, `/music/nope`, lands on Songs.

**Notes:** Cards are keyed `music_album_<albumKey>`, rows `music_artist_<name>` and `music_genre_<name>`.

---

### JN-MU-004: Open an album

**Preconditions:** JN-MU-003 passes.

**Steps:**

1. On `/music/albums`, tap an album.
2. Tap the back button.

**Expected result:**

- The album's page opens at `/music/albums/<albumKey>`: its cover, title, artist, year and track count above its songs
  in album order (disc, then track number).
- Back returns to `/music/albums`.

**Notes:** Two albums with the same title by the same artist in different folders are separate albums.

---

### JN-MU-005: Open an artist

**Preconditions:** JN-MU-003 passes.

**Steps:**

1. On `/music/artists`, tap an artist.
2. Tap one of their albums.

**Expected result:**

- The artist's page opens at `/music/artist?name=<name>`: their albums as cards, then their songs by album.
- Tapping an album opens its page (JN-MU-004).

**Notes:** Songs with no artist tag are listed as **Unknown artist**, and its page shows them. The name is in the query
so a `/` in it (AC/DC) survives.

---

### JN-MU-006: Songs in one genre

**Preconditions:** JN-MU-003 passes.

**Steps:**

1. On `/music/genres`, tap a genre.
2. Tap the chip's clear button.

**Expected result:**

- Songs opens at `/music/songs?genre=<name>`, showing only that genre's songs, with a chip naming the genre.
- Clearing the chip returns to `/music/songs` with every song.

**Notes:** Songs with no genre tag are **Unknown genre**, at `/music/songs?genre=`. The chip is keyed
`music_genre_filter`.

---

### JN-MU-007: Search the library

**Preconditions:** JN-MU-001 passes. The Quark uses SQLite.

**Steps:**

1. On `/music`, type part of a title, artist, album or genre in the search box.
2. Tap the box's clear button.

**Expected result:**

- Once typing pauses, the tabs give way to the matching songs, best match first, each with the text that matched.
- No match says **No matches**.
- Clearing the box shows the tabs again.

**Notes:** On a Quark using PostgreSQL the search says it is not supported yet (#2958). The box is keyed
`music_search_field`, its clear button `music_search_clear`.

---

### JN-MU-008: No music yet

**Preconditions:** User is logged in. No audio file the user can read has been scanned.

**Steps:**

1. Navigate to `/music`.
2. As an admin, tap **Scan music**.

**Expected result:**

- The page says **No music yet**. An admin also sees **Scan music**; anyone else does not.
- While a scan is queued or running the page says **Scanning your music**, and the scan shows in the jobs badge.
- When the scan finishes the page fills in by itself.

**Notes:** The page fetches again on the `music_library_changed` event, which the Quark sends as files are added,
moved or deleted and when a scan finishes. The button is keyed `music_scan`.

---

### JN-MU-009: Rescan the library from Settings

**Preconditions:** User is logged in as an admin.

**Steps:**

1. Navigate to `/settings/general`.
2. Under the storage devices link, tap **Rescan music library**.

**Expected result:**

- The card says **Scan started. Its progress shows in Jobs.**, and a music rescan appears in the jobs badge.
- A refusal is worded as a sentence, never a raw error.

**Notes:** The card is shown to admins only. The library keeps itself current as files change, so a rescan is for tags
edited elsewhere or a drive changed while unplugged. Keys: `settings_music_rescan`, `settings_music_rescan_queued`,
`settings_music_rescan_error`.
