# Music library: scan, tags, cover art, search

**Status: approved design, in progress.** Design for #2982 under the local media epic #2993. The owner approved its
recommendations: the tag reader and the index both follow the recommended option. The schema, the `musicutil`
service, the indexer and cover art have landed; the sections below still describe the HTTP API and the app, which
are being built as the sub-tickets land.

## What the issue asks for

A library built from the audio files already on the device: mp3, flac, ogg/opus, m4a/aac, wav and wma. It
reads title, artist, album, track and disc, year, genre and duration. It has Songs, Albums, Artists and Genres
views, a search over the tags, and cover art from embedded pictures or a `cover.jpg` / `folder.jpg` beside the
track. A local play history ranks Recently played and Most played. Tag editing is a stretch goal that waits on
version snapshots (#2934) and is out of scope here.

The constraints come from the issue and the epic:

- **Nothing leaves the device.** No metadata lookups and no fingerprinting service.
- **No ffmpeg and no decoding on the device** (#2378). Tags and container headers are read in pure Go, and
  playback stays on the client, as `AudioPlayerPage` does today.
- **Per-user access rules hold.** A listing, a search hit, a cover or an event about a file the caller cannot
  read never reaches them. The vault holds secrets in the database, not files, so the files tree has nothing
  end-to-end encrypted to exclude today. The scan still skips the trash, the version stores and in-flight
  writes (`storageutil.IsInternalName`, `IsTrashPath`), as the content index does.
- **Streaming and memory rules** from `AGENTS.md`. A 500 MB FLAC costs the scan a few kilobytes of reads, not
  500 MB of heap.

## What already exists to build on

| Piece                                   | What it gives the music library                                                       |
| --------------------------------------- | ------------------------------------------------------------------------------------- |
| `internal/server/content_indexer.go`    | the event-driven indexer: subscribes to the bus, upserts on upload, deletes on delete, both on move, backfills on startup, on `resync`, and when a drive appears; drops a drive's rows when it goes |
| `pkg/util/searchutil`                   | an FTS5 external-content table kept in step by triggers, the query sanitizer, and the access-filtered paging in `SearchReadable` |
| `pkg/util/indexutil`                    | the file index, a table with a trigram index kept current from events and reconciled at startup (#2956) |
| `pkg/util/thumbnailutil`                | size tiers, the on-disk cache under `<data>/cache/thumbnails`, ETags, the IO semaphore classes |
| `pkg/vfs`                               | `vfs.Walk`, `VFS.Open` returning a seekable `vfs.File`, one namespace per device, `MetadataStore` (`vfs_metadata`) |
| `pkg/util/playbackutil`                 | per-user state in `vfs_metadata` under `playback.<user id>`, with no table of its own |
| `pkg/util/jobutil`                      | durable jobs with progress events, visible in the jobs badge                          |
| `pkg/util/accessutil`                   | `Check` per path, `FilterEvent` per subscriber                                        |
| `storageutil.AudioMIMETypeFromExtension`, `lib/utils/file_kind.dart` | the audio extension list on each side             |

## Decision 1: how tags are read

The parser runs on files any user with upload rights can write, so it is attack surface. A malformed or
hostile tag should cost one failed row. It must not cost the process its heap.

### Option T1: `github.com/dhowden/tag`, plus small readers of our own for duration and the gaps (recommended)

- **What it reads:** ID3v1 and ID3v2.2–2.4 (mp3), MP4 atoms (m4a, aac in MP4, ALAC), FLAC Vorbis comments and
  picture blocks, Ogg Vorbis comments and `OpusTags`, and DSF. It takes an `io.ReadSeeker`, which is what
  `vfs.File` already is, so nothing is buffered to make it seekable.
- **What it does not read:** duration, WAV (RIFF `INFO` / `id3 ` chunk) and WMA (ASF). We would write those, and
  each is a small fixed-layout header read: FLAC `STREAMINFO` (sample count over rate), the MP4 `mvhd` atom,
  the last Ogg page's granule position (one seek to the end), the MP3 Xing/Info or VBRI header with a
  bitrate-from-size estimate when neither is present, the WAV `fmt `/`data` chunk sizes, and the ASF File
  Properties object. A raw ADTS `.aac` has no duration header; its bitrate estimate is marked approximate.
- **License and upkeep:** BSD-2-Clause, about 650 stars, last commit April 2024. It is quiet, not abandoned:
  the format is stable and so is the code.
- **Attack surface:** two known defects, both open upstream. #116 is an unbounded allocation in
  `readPictureBlock` from a length field the file controls, and #115 is the pull request that bounds it. #87 is
  a panic on odd-length UTF-16 text. Mitigations, all in our wrapper:
  1. Before handing a file to the library, read the container's own size fields ourselves: the ID3 header's
     tag size, FLAC metadata block lengths, the MP4 `moov` size. Refuse any above `MaxTagBytes` (16 MiB), or
     above the file's size from `Stat`. That bounds what the library can ask `make` for.
  2. Call it under `recover()`, so a panic costs one track.
  3. Fuzz the wrapper (`go test -fuzz`) with a corpus of real files from each format, in CI as a seed-only run.
  4. Pin the version, and offer #115 upstream rather than forking. A fork needs the owner's approval
     (`AGENTS.md`).
- **Cost:** one new direct dependency with no transitive ones, and roughly 400–600 lines of our own readers
  and tests.

### Option T2: write every parser ourselves

A `pkg/util/audiotagutil` that reads ID3, MP4, FLAC, Vorbis comment, RIFF and ASF directly. We control every
allocation, so the size checks are built in rather than bolted on, and there is no dependency. The cost is
roughly 2,000–3,000 lines plus a fuzz corpus. ID3's history makes it the bulk of that: v2.2 three-letter
frames, unsynchronization, the four text encodings, and v2.4's syncsafe frame sizes, which half the encoders
in the wild got wrong. A real option if T1's wrapper turns out leaky, and a poor first move.

### Option T3: shell out to ffprobe or exiftool (not recommended)

ffprobe is ruled out by #2378: the device ships no ffmpeg. exiftool is Perl. It reads everything, but it is a
process spawn per file, costing tens of milliseconds on the small ARM boards (a 20,000-track library becomes
minutes of fork and Perl start-up), and it is a large parser in a second language. It also makes the device
image a dependency of a core feature, which `AGENTS.md` keeps as a last resort. `photoutil` uses exiftool only
as a RAW fallback, behind the `Raw` semaphore class, and is not a pattern to extend.

### Option T4: TagLib through cgo (not recommended)

`wtolson/go-taglib` (BSD-3, untouched since 2021) and `sentriz/audiotags` (LGPL-2.1, archived) wrap the C++
TagLib. TagLib is the most complete reader there is. But cgo breaks the plain cross-compile to
`darwin/arm64` and `linux/arm64` that CI runs, and C++ parsing of untrusted input moves the crash domain from
"one track" to "the server".

For completeness: `mewkiz/flac` (Unlicense), `abema/go-mp4` (MIT), `n10v/id3v2` (MIT, last push 2023) and
`jfreymuth/oggvorbis` (MIT) each cover one format well. Stitching four of them together is T1 with more
dependencies. `abema/go-mp4` is the one worth reaching for if our own `mvhd` reader proves fiddly.

## Decision 2: where the index lives

`AGENTS.md` makes the database a last resort. So each option below is weighed by what it costs the queries the
views need, not just by whether it adds a table. The queries are: list the albums of an artist, sorted and
paged; count the tracks in a genre; search title, artist and album with ranking; and do all of it for a
non-admin who can read only part of the tree.

### Option A: one derived table and an FTS5 mirror (recommended)

```sql
-- SQLite; the PostgreSQL pair has the same columns with BIGINT / TEXT and no FTS table.
CREATE TABLE music_tracks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    serial          TEXT    NOT NULL,           -- '' for the internal drive
    rel_path        TEXT    NOT NULL,
    size            INTEGER NOT NULL,           -- with mtime, the "has it changed" check
    mtime           INTEGER NOT NULL,
    scanner_version INTEGER NOT NULL,           -- bumped when parsing improves, forces a re-read
    title           TEXT    NOT NULL DEFAULT '',-- the file name without extension when untagged
    artist          TEXT    NOT NULL DEFAULT '',
    album_artist    TEXT    NOT NULL DEFAULT '',-- falls back to artist
    album           TEXT    NOT NULL DEFAULT '',
    album_key       TEXT    NOT NULL DEFAULT '',-- hex hash of lower(album_artist) NUL lower(album) NUL folder
    genre           TEXT    NOT NULL DEFAULT '',
    track_no        INTEGER, disc_no INTEGER, year INTEGER,
    duration_ms     INTEGER,
    duration_exact  INTEGER NOT NULL DEFAULT 1, -- 0 for a bitrate estimate
    cover_source    TEXT    NOT NULL DEFAULT '',-- 'embedded', 'folder:<name>', or ''
    cover_key       TEXT    NOT NULL DEFAULT '',-- sha256 of the picture bytes; shared by an album
    UNIQUE(serial, rel_path)
);
CREATE INDEX idx_music_tracks_album  ON music_tracks (album_key);
CREATE INDEX idx_music_tracks_artist ON music_tracks (LOWER(album_artist));
CREATE INDEX idx_music_tracks_genre  ON music_tracks (LOWER(genre));
CREATE VIRTUAL TABLE music_tracks_fts USING fts5(
    title, artist, album_artist, album, genre,
    content=music_tracks, content_rowid=id,
    tokenize='unicode61 remove_diacritics 2'    -- no porter: stemming names helps nobody
);
-- plus the three sync triggers, as 006_file_search does for file_content
```

- **Why this is the last resort that applies.** Browsing needs `GROUP BY`, `ORDER BY` and `LIMIT` across tens
  of thousands of rows. SQLite does that from an index with a few pages of cache. Every non-database option
  below either holds the whole library in heap or decodes it on every request.
- **It is a cache, not a record.** Every column is derived from the files. Dropping the table loses nothing: a
  rescan rebuilds it, and `scanner_version` makes a parser fix re-read old rows. The files stay the source of
  truth, which is the intent behind the rule. The one non-derived thing, play history, stays out of the table
  (see Play history).
- **Album identity** is `album_key`. Including the folder splits two different albums both called "Greatest
  Hits" by the same artist. It also splits one album copied into two folders, which is what a user who did that
  expects to see.
- **Search** is FTS5 with column filters, so `artist:nina` works, ranking, and `snippet()`. It reuses
  `searchutil`'s sanitizer (exported for the purpose) and its access-filtered paging.
- **PostgreSQL:** the table and every browse query are shared sqlc queries and run on both engines. Search is
  raw FTS5 behind `db.RequireSQLite(..., "Music search", 2958)`, exactly like content search, and is added to
  the not-on-PostgreSQL list in [data.md](data.md#what-does-not-work-on-postgresql-yet). When #2958 gives
  content search a `tsvector`, music search follows the same pattern.
- **Size:** about 300 B a row plus the FTS index. A 20,000-track library is around 10 MB on disk, 0 bytes of
  resident heap.
- **Cost:** a migration pair in each engine's set, one `sql/queries/music.sql`, regenerated `internal/db`.

### Option B: no new table, reusing `vfs_metadata` and `file_content`

Tags go into `vfs_metadata` as JSON under the key `music.tags`, one row per track, as `playbackutil` stores
positions. A one-line text form ("title — artist — album — genre") goes into `file_content`, so the existing
FTS5 index and content search find songs.

- **For it:** zero migrations, and songs turn up in the global content search for free.
- **Against it:** every browse request reads every `music.tags` row (`idx_vfs_metadata_ns_key` makes that one
  index range scan, but still the whole library) and decodes the JSON, then groups and sorts in Go. That is
  about 6 MB of JSON and 20,000 `json.Unmarshal` calls per request at 20,000 tracks. The one FTS column has
  porter stemming and no field filters, so `artist:` searches are impossible and snippets show the synthetic
  line. Nothing rewrites `vfs_metadata` on a move today (see `playbackutil`'s package doc), so this needs that
  mechanism built first. And the content index's backfill re-extracts every file each pass, which for audio
  means re-reading every tag on every start.
- **Verdict:** saves a migration and pays for it on every page view. It works up to a few thousand tracks.

### Option C: an in-memory index, persisted to a cache file

Build the library in heap the way `indexutil.FileIndex` holds file names, keep it current from events, and
persist it to `<data>/cache/music/<serial>.jsonl` so a restart does not rescan. Search is a substring match
over the in-memory rows.

- **For it:** no database at all, and the fastest browse.
- **Against it:** around 250 B a track in heap, with strings interned. That is 5 MB at 20,000 tracks and
  25 MB at 100,000, held for the life of the process on boxes `capacity.md` counts megabytes on. Every
  instance on a shared database (#2966) holds its own copy and scans on its own. It gets no ranking and no
  tokenization beyond what we write. And it is a second persistence format to version and recover from a
  half-written file.
- **Verdict:** right for file names, which every page needs. Wrong for a feature many users never open.

**Recommendation: A.** It is the only option whose cost does not grow with the library on every request, and
it stays a cache that a rescan rebuilds.

## Where the scan runs

A **`music-indexer` bus subscriber** started beside `startContentIndexer` in `internal/server/server.go`, with
the same shape and the same device handling:

- `upload` → read tags and upsert the row. `delete` → delete the row, or every row under the path, since a
  folder delete names only the folder. `move` → rewrite `rel_path` for the path and everything under it in one
  `UPDATE`, not a delete-and-rescan, so moving an album folder costs no reads. `resync` and a newly mounted
  drive → backfill that device. An unmounted drive → delete its rows, as `contentDevices.sync` does.
- **The backfill is incremental**, unlike the content index's. A file whose `size`, `mtime` and
  `scanner_version` match its row is not opened. A row whose file the walk did not see is deleted at the end of
  the pass. A content backfill re-reads 512 KB per document. Re-reading every track's tags on every start would
  mean one seek per file on a spinning USB drive: an estimated 5–10 minutes per 20,000 tracks, which we should
  not pay at each boot.
- **A full rescan is a `jobutil` job**, kind `music_rescan`, queued by an admin from Settings and on first
  start. The job runs the same backfill, reports `scanned/total` through `job_progress`, and shows in the jobs
  badge. The event-driven path is not a job: one row per upload does not need a durable record.
- **Reads go through `pkg/vfs`.** `registry.Get(vfs.FilesNamespace(serial))`, `vfs.Walk`, and `VFS.Open` for a
  seekable `vfs.File`. No `HostPather`: nothing is handed to an external process. `scripts/check-go-structure.bash`
  needs no allowlist entry.
- **Memory:** one file open at a time per device, with the tag region bounded by `MaxTagBytes`. An embedded
  picture is hashed (`sha256`) and dropped as soon as it is read. The scan stores the hash, not the bytes, and
  the cover is read again only when a thumbnail is generated. Peak heap is one tag region, 16 MiB at worst and
  usually a few kilobytes. Each file gets a 5 s timeout through its context, as `indexTimeout` does for content.
- **Multi-instance:** every instance's subscriber upserts the same rows idempotently, as the content indexer
  already does, so duplicate work is waste and not corruption. The rescan job's claim makes one instance run it.

## Cover art

- **Source order:** an embedded front-cover picture (ID3 `APIC` type 3, else the first picture; the FLAC
  picture block; MP4 `covr`). If there is none, the first of `cover`, `folder`, `front` and `album` with a
  `.jpg`, `.jpeg` or `.png` extension, matched case-insensitively, in the track's folder. Embedded comes first
  because compilations and mixed folders are where folder art is wrong. The scan records which one it found in
  `cover_source`.
- **Serving:** through the existing `GET /api/v0/thumbnails/...` with the track's path, so the client changes
  nothing but the path it asks for. `thumbnailutil` gains an audio branch. `ErrNotMedia` stops applying to
  audio extensions. `Prepare` looks up the row, and generation decodes the embedded picture (re-read through the
  same bounded tag reader) or opens the folder image through `VFS.Open`. It then resizes into the usual tiers
  under the `Decode` semaphore class. A track with no cover answers 404, and the client draws a placeholder.
- **Caching:** the cache key for audio is `cover_key` plus size, not the track's path. Twelve tracks of an
  album share one cached thumbnail per size, and a rescan that finds the same picture keeps the cache warm.
  Access is checked on the requested track, as for any thumbnail, so a shared cache entry leaks nothing.
- **No client-rendered thumbnails** (#2379) are needed: cover art is JPEG or PNG, which Go decodes.

## Search

`musicutil.Search` runs `music_tracks_fts MATCH ?` ranked by `bm25` and pages it through the same
"fetch twice the limit, keep the readable ones" loop as `searchutil.SearchReadable`. That loop moves into a
small shared helper rather than being copied. A result is a track, with the matched column highlighted in a
snippet. Songs do **not** join the global content search: a song hit belongs in the Music page, and mixing tag
lines into document snippets would make both worse. That is a one-line change later if the owner wants it.

Browse views filter by access the same way: an admin's request is one SQL aggregate, and a non-admin's streams
the matching rows (`serial, rel_path, album_key, …`) through `accessutil.Check` and aggregates in Go. That
costs one pass per request for a user with partial access, bounded by the number of rows and never holding
more than one group per album or artist. The same `ponytail:` note as `SearchReadable` applies: move to a
`path_access` join if it measures slow.

## Events

- **Consumed:** `upload`, `delete`, `move` and `resync` from the bus, as above. The subscriber is a queued
  subscriber, so a burst coalesces per path, and an overflow becomes a `resync`, which runs an incremental
  backfill.
- **Published:** a new `music_library_changed` kind. It carries the device serial and no path, and is
  debounced: at most one per device per 2 s while changes keep landing, plus one when a scan finishes. Open
  Music pages fetch again on it. `accessutil.FilterEvent` passes it to everyone, as it does `trash_changed`:
  the event only says "fetch again", and that fetch is access-filtered.
- **The rescan job** publishes the usual `job_*` events, so its progress shows in the jobs badge.

## API

A new package `internal/server/api/v0/music` (`package v0_music`), mounted in `apiRouters`, with rescan in the
`adminGroup` block. Swagger tag `music`. One handler per file, with logic in `pkg/util/musicutil`.

| Method and path                         | File                  | Returns                                                                |
| --------------------------------------- | --------------------- | ---------------------------------------------------------------------- |
| `GET /music/tracks`                     | `list_tracks.go`      | `{tracks: Track[], total}`; filters `albumKey`, `artist`, `genre`; `sort=title\|artist\|album\|added\|year`, `order`, `offset`, `limit` (clamped to 200) |
| `GET /music/albums`                     | `list_albums.go`      | `{albums: Album[], total}`; `Album` is `albumKey, title, albumArtist, year, trackCount, durationMs, coverPath` (a track path to ask the thumbnail endpoint for) |
| `GET /music/artists`                    | `list_artists.go`     | `{artists: [{name, albumCount, trackCount, coverPath}], total}`        |
| `GET /music/genres`                     | `list_genres.go`      | `{genres: [{name, trackCount}]}`                                       |
| `GET /music/search?q=`                  | `search_music.go`     | `{results: [{track: Track, snippet}]}`; 501 on PostgreSQL until #2958  |
| `GET /music/status`                     | `get_status.go`       | `{trackCount, lastScanAt, scanJobId?}`, so an empty page can say "scanning" rather than "no music" |
| `POST /music/rescan` (admin)            | `rescan_library.go`   | 202 with the queued `Job`                                              |
| `POST /music/plays`                     | `record_play.go`      | 204; body `{serial, relPath}`                                          |
| `GET /music/history?sort=recent\|most`  | `list_history.go`     | `{tracks: [{track: Track, playCount, lastPlayedAt}]}`                  |

`Track` is `serial, relPath, title, artist, albumArtist, album, albumKey, genre, trackNo, discNo, year,
durationMs, durationExact, hasCover`. Streaming the audio is the existing file download with range requests.
Cover art is the existing thumbnail route.

## Play history

Per user and local, as the issue asks. It is not derived from files, so it goes in `vfs_metadata` under
`music.plays.<user id>` as `{count, lastPlayedAt}` per track, the same store and keying `playbackutil` uses.
That means no table and no column on `music_tracks`. Most played and Recently played list that user's rows by
key (indexed) and sort in Go; the set is bounded by the tracks one person has played. The client decides when a
play counts (30 s, or half a track shorter than 60 s, Spotifast's rule) and posts it once. The server only
counts. Moving a file drops its history, the same known limit `playbackutil` documents. The epic's shared
resume position (#2984) is a separate mechanism and does not share this key.

## Flutter surface

- **Route and page:** `AppRoutes.music` (`/music`), tabbed per #2349 with a `MusicTab` enum (`songs`,
  `albums`, `artists`, `genres`) through `tabbedRoutes`. Detail pages `/music/albums/:albumKey` and
  `/music/artists/:name` use `context.go`, so they deep-link. A drawer entry sits beside Photos.
- **App code:** `lib/services/music_service.dart`, `lib/models/music_track.dart` (and album, artist, genre),
  and `lib/controllers/music_controller.dart`, a `ChangeNotifier` with injectable service calls that fetches again on
  `music_library_changed`. Thin pages: `music_page.dart`, `music_album_page.dart` and `music_artist_page.dart`,
  using `AutoRefreshMixin` with `onRefresh` in the app bar slot. Errors go through `Errors.message`.
- **Package widgets** (`packages/quark_widgets/lib/src/music/`): `TrackListTile`, `AlbumGridTile`,
  `ArtistListTile`, `GenreListTile`, `MusicCoverArt` (a `coverBuilder` slot plus placeholder),
  `MusicSearchResults`, and `MusicLibraryEmptyState` (with "scanning" and "no music yet" states). Key prefixes:
  `music_track_<path>`, `music_album_<albumKey>`, `music_artist_<name>`, `music_genre_<name>`. Each ships with
  its test (narrow and wide) and its gallery entry.
- **Playing:** tapping a track opens the existing `AudioPlayerPage`. The queue, shuffle and gapless playback are
  #2983. The player posts `/music/plays` when the play threshold is crossed.
- **Settings:** an admin "Rescan music library" action that queues the job.
- **Journeys:** a new `docs/user-journeys/music.md` with `JN-MU-*` entries once the page ships.

## Sub-tickets, in landing order

Each lands on its own. Claims are disjoint between tickets that can run at the same time; a ticket that edits
a file an earlier one created says so and lands after it. The backend API (5) and the Flutter page (8) form one
stack, as `AGENTS.md` requires for a new endpoint.

1. **Bounded tag reader.** `pkg/util/audiotagutil`: wraps `dhowden/tag` behind the size pre-checks and
   `recover()`, adds the duration readers and the WAV and WMA tag readers, and returns
   `Tags{…, Picture *PictureRef}` from a `vfs.File`. Includes a fuzz test and seed corpus, and a heap test
   showing a tag declaring 1 GiB fails without allocating it.
   **Difficulty: hard (parsers of untrusted input, allocation safety).**
   Claims: `pkg/util/audiotagutil/**`, `go.mod`, `go.sum`, `.vscode/cspell.json`.
2. **Schema and queries.** Migration pair `NNN_music_library` in both sets (FTS table and triggers SQLite-only),
   `sql/queries/music.sql` (upsert, delete by path or prefix, move by prefix, delete by serial, the
   browse aggregates, and the unchanged-file check), regenerated `internal/db`. Add the table to `data.md`.
   **Difficulty: standard (two-engine SQL rules).**
   Claims: `internal/db/migrations/NNN_music_library.*`, `internal/db/migrations_postgres/NNN_music_library.*`,
   `sql/queries/music.sql`, `internal/db/` generated files, `docs/architecture/data.md`.
3. **Library service.** `pkg/util/musicutil`: `IndexTrack`, `BackfillDevice` (incremental, with deletion of
   unseen rows), `DeletePath`, `MovePath`, `DropDevice`, the browse functions with access filtering, and
   `Search` behind `RequireSQLite`. Exports `searchutil`'s sanitizer and readable-paging helper for reuse.
   Depends on 1 and 2.
   **Difficulty: hard (access filtering of aggregates, incremental scan correctness).**
   Claims: `pkg/util/musicutil/**`, `pkg/util/searchutil/search.go`, `pkg/util/searchutil/searchutil.go`.
4. **Indexer wiring and events.** `internal/server/music_indexer.go` (the subscriber, device sync and
   debounced `music_library_changed`), the `music_rescan` job kind, the new event kind, and its `FilterEvent`
   case. Depends on 3.
   **Difficulty: standard.**
   Claims: `internal/server/music_indexer.go`, `internal/server/server.go`, `pkg/util/eventbus/eventbus.go`,
   `pkg/util/accessutil/accessutil.go`, `pkg/util/accessutil/filter_event_test.go`.
5. **Music API.** `internal/server/api/v0/music/**`, all routes but plays and history, mounted in `routes.go`,
   with swagger and integration tests including the access cases. Depends on 3.
   **Difficulty: standard.**
   Claims: `internal/server/api/v0/music/**`, `internal/server/routes.go`, `docs/swagger/**`.
6. **Cover art through thumbnails.** The audio branch in `thumbnailutil` (source order, `cover_key` cache key,
   404 with no cover) and the handler's media check. Depends on 1 and 3; can run beside 4 and 5.
   **Difficulty: standard.**
   Claims: `pkg/util/thumbnailutil/**`, `internal/server/api/v0/thumbnails/**`.
7. **Music widgets.** The package widgets listed above, with tests and gallery entries. Needs only the API
   shape in this doc, so it can start at once.
   **Difficulty: standard.**
   Claims: `packages/quark_widgets/lib/src/music/**`, `packages/quark_widgets/test/music/**`,
   `packages/quark_widgets/lib/quark_widgets.dart`, `packages/quark_widgets/examples/widget_gallery/lib/registry.dart`,
   `packages/quark_widgets/examples/widget_gallery/lib/docs.g.dart`.
8. **Music page.** Service, models, controller, the three pages, routes, the drawer entry, the Settings rescan
   action, tests, and `docs/user-journeys/music.md`. Stacked on 5; uses 7.
   **Difficulty: standard.**
   Claims: `lib/services/music_service.dart`, `lib/models/music_*.dart`, `lib/controllers/music_controller.dart`,
   `lib/pages/music_*.dart`, `lib/widgets/music/**`, `lib/router.dart`, `test/**/music_*`,
   `docs/user-journeys/music.md`, `docs/user-journeys/README.md`.
9. **Play history.** `pkg/util/musicutil/history.go` (store in `vfs_metadata`), `record_play.go` and
   `list_history.go` in the music API, the player's threshold and post, and Recently and Most played sections
   on the page. Lands after 5 and 8, since it edits the music package's `types.go` and the page.
   **Difficulty: standard.**
   Claims: `pkg/util/musicutil/history*.go`, `internal/server/api/v0/music/{record_play,list_history,types}.go`,
   `docs/swagger/**`, `lib/pages/audio_player_page.dart`, `lib/controllers/music_controller.dart`,
   `lib/pages/music_page.dart`.
10. **Docs index.** Link this page from `docs/architecture/README.md` and drop its "proposal" status once 4 lands.
    **Difficulty: mechanical.**
    Claims: `docs/architecture/README.md`, `docs/architecture/music-library.md`.

Tag editing (#2982's stretch goal) is not on the list. It waits on #2934, and it writes to user files, which
makes it a design of its own.

## Open questions for the owner

- **Option A over B:** it accepts a new table on the grounds that the table is a cache a rescan rebuilds. If the
  database rule is meant to cover caches too, B is the fallback, with the browse costs above.
- **Songs in global content search:** left out on purpose (see Search). Say if they should be in.
- **Rescan on first start:** the proposal queues one automatically. On a large USB library that is minutes of
  disk activity the user did not ask for. The alternative is to wait until the Music page is first opened.
