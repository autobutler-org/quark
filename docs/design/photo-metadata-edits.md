# Photo date and location edits

**Status: Proposed.** Nothing here is built. Covers #4174 (fix a photo's date, time and time zone) and #4175
(edit or remove a photo's location without touching the file). The open questions at the end need the owner's
answer before either ticket is ready to work.

## The problem

A photo's capture date and position come from its EXIF block. When those are wrong or missing, the photo lands
in the wrong place. A camera clock left on home time puts a trip on the wrong day. A scanned print has no date and
sorts by when it was scanned. A photo a friend sent shows the friend's GPS. Today the only fix is an outside tool
that rewrites the file, and Quark promises the opposite: the original file is never changed.

Both tickets want the same thing: an **override** stored beside the photo that wins everywhere Quark reads the
value, plus **Revert to original**. This proposal designs the two together. They share the storage, the API
shape, the access rule, bulk editing, undo, and the move and delete bookkeeping. Captions (#16 in the same audit)
should be able to reuse the same design later.

## What exists today

- **The capture date.** `photoutil.DecodeExif` (`pkg/util/photoutil/exif.go`) calls imagemeta's `GetDateTime`
  and stores the result as UTC. When the EXIF has no offset, imagemeta reads the wall-clock time in the
  **Quark's own zone** (`time.Local`). So `taken_at` is the right instant only when the camera and the Quark
  were in the same zone. The offset itself is not kept, and the info panel cannot show "13:02 UTC+1".
- **The library index.** `photo_hashes` holds one row per library photo: hashes, `taken_at`, `taken_checked`
  (migration 020), and `latitude` and `longitude` (migration 049 in #4279, the Locations view). It is a
  **cache**. `movePhotoRows` (`pkg/util/fileutil/helpers.go`) drops the row on move rather than carrying it
  (#1666), and migration 049 clears `taken_checked` so every photo is read again. Anything stored there that the
  file cannot give back would be lost.
- **Sort and grouping.** `fillTakenDates` and `sortPhotos` (`pkg/util/photoutil/list.go`) load every stored
  date into a map and sort in Go. Month headers (JN-PH-020) and the Taken sort (JN-PH-018) follow that value.
- **A precedent: rotation.** `photo_rotations` (migration 004) is already a per-photo, non-destructive edit
  kept on the server. `POST /photos/rotate` checks `accessutil.Write`, because "rotation describes the file, so
  everyone who can see it sees it turned" (#1904). Date and location are the same kind of fact.
- **Per-path metadata.** `vfs_metadata` (migration 007) holds JSON key/value pairs per `(namespace, path, key)`.
  Playback position uses it through `deps.MetadataStore()`.
- **Move and delete.** `movePhotoRows` carries favorites and album items. `DeleteFiles` removes album items,
  favorites, rotation and hash rows. Neither touches `vfs_metadata`. Rotation is cleaned on delete but **not
  carried on move** today, which looks like a bug in its own right (see Open questions).
- **Selection.** JN-PH-027 (#4275) gives a selection bar on All photos and in albums, with a **More** menu on a
  phone. Today it runs one request per photo, four at a time, and reloads once at the end.
- **Location opt-in.** #3572 (open) decides whether Quark stores GPS at all. #4279 stores it, and its follow-up
  #4277 makes the map opt-in per account.

## User flow

The people this is for are not power users (see the project's audience note). They think "this photo is from the
wrong day" or "this was in Lisbon", not "EXIF offset".

### One photo, from the viewer

The info panel (JN-PH-013, `lib/widgets/image_viewer/metadata_content.dart`) already shows the date and, after
#4279, a still map preview. Each row gains an edit affordance. It shows only to someone who can write to the
photo's folder.

- **Date row:** "Tue 14 May 2024, 14:02 · UTC+1". When the date is edited, a second line reads "Camera said
  13:02". A pencil button opens **Edit date and time**.
- **Edit date and time** has a date picker, a time picker, and a time zone dropdown. The dropdown lists offsets
  ("UTC+1"), not zone names: an offset is what EXIF stores, and a list of 400 zone names is hard to scan.
  **Save**, **Cancel**, and **Revert to original** when an edit exists. On a phone it is a full-height bottom
  sheet; on desktop a dialog.
- **Location row:** the map preview, then **Edit location** and **Remove location**. When the location is
  edited or removed, the row says so ("Location removed" or "Location set on this Quark") and offers **Revert to
  original**.
- **Edit location** opens a map, the same `flutter_map` stack and tile settings as the Locations view, with a
  draggable pin. A **Coordinates** field accepts `38.7223, -9.1393` for anyone who has them. There is no place
  search: Quark makes no third-party calls, so a place is a pin. When the photo map is off (#4277), the map is
  replaced by the coordinates field alone.
- If location is not stored for this account (#3572), the location controls do not show at all.

### A selection, from the grid

The JN-PH-027 bar gains **Adjust date** and, when location is on, **Edit location**. On a phone both go in the
**More** menu. On desktop they go in the bar.

**Adjust date** has three tabs:

1. **Shift** (default): "Move 37 photos by [+][1] [hours ▾]". Keeps the gaps between photos. A preview shows the
   first and last photo's date before and after.
2. **Time zone:** "These photos were taken in [UTC+1 ▾]". Shown when the selection's current offsets agree, or
   are unknown. It is a shift by the difference between the old and the new offset, so "from UTC-5 to UTC+1" is
   +6 hours on the wall clock.
3. **Set one date:** "All 37 photos were taken on [date]", time optional. This is for a box of scanned prints.
   The photos keep their relative order by giving each one the chosen date plus its index in seconds, so they do
   not shuffle under the Taken sort.

**Edit location** on a selection offers **Set one location** (the same pin picker) and **Remove location**.

Every bulk action takes one confirmation step when it touches more than one photo ("Shift 37 photos by +1
hour?"), runs as one request, and ends with a snack bar: "Shifted 37 photos. **Undo**".

### Undo and revert

There are two different things here, and the UI keeps them apart.

- **Undo** (snack bar, a few seconds): puts back exactly what was there before this action. That may itself be
  an earlier edit.
- **Revert to original** (info panel, or a selection's menu): drops the override so the EXIF value shows again.
  It is undoable too.

### What a read-only viewer sees

The date and location in use, with the "Camera said" line, and no edit buttons. The server refuses the edit
anyway (403).

## Where edits are stored

AGENTS.md says to add tables only as a last resort and to prefer files. So the question is whether this state can
live on disk.

It cannot live **in** the photo. Both tickets require the file to stay byte-for-byte unchanged, and a read-only
USB drive could not be written anyway. It also cannot live in `photo_hashes`. That table is a cache the code drops
on move and re-reads at will, and an override is the one thing the file cannot give back. That leaves three
places.

### Option A: a `photo_edits` table (recommended)

One row per edited photo, keyed like `photo_rotations` and `favorites`:

```sql
CREATE TABLE photo_edits (
    device_serial      TEXT NOT NULL DEFAULT '',
    rel_path           TEXT NOT NULL,
    taken_at           DATETIME,   -- NULL: no date edit
    taken_offset_min   INTEGER,    -- minutes east of UTC; NULL: unknown
    location_state     TEXT,       -- NULL: no edit; 'set' or 'removed'
    latitude           REAL,
    longitude          REAL,
    updated_at         DATETIME NOT NULL,
    updated_by         INTEGER,    -- the account that made the edit
    PRIMARY KEY (device_serial, rel_path)
);
```

The PostgreSQL pair uses `TIMESTAMPTZ` and `DOUBLE PRECISION`. A row whose every edit is NULL is deleted, so
**Revert to original** of the last edit removes the row.

- **For:** the queries are typed, and sqlc checks them against the schema on both engines. A date range filter
  (#3496) can run in SQL. It follows two precedents that `movePhotoRows` and `DeleteFiles` already handle row by
  row (favorites, rotation). Captions can be one more column. One upsert per photo, in one transaction, makes a
  200-photo shift fast and all-or-nothing.
- **Against:** it is a new table and a migration pair. Like albums and favorites, it is not in a drive backup.
  A lost internal disk loses the edits, though a bundle (`quark bundle export`) keeps them.

**Why the database is justified here.** The data is user-made state that by requirement cannot go in the file.
It has to be read for every listing and every map load. Every other per-photo edit Quark has already lives in the
database. A sidecar file (Option C) makes the user's folders the database instead, and pays for it in the places
listed below.

### Option B: keys in the existing `vfs_metadata` table

Store `photos.taken` (`{"at": "...", "offsetMin": 60}`) and `photos.location` (`{"state": "removed"}` or
`{"lat": ..., "lon": ...}`) as keys on the photo's `(namespace, path)`. The namespace is `files` or
`files:<serial>`.

- **For:** no new table and no migration. The store, its queries, and `deps.MetadataStore()` already exist. A
  removed key is a revert.
- **Against:** the values are JSON that sqlc cannot check, and reading them in SQL is engine-specific
  (`json_extract` and `->>`). So every date and location consumer merges in Go, and a date range filter cannot
  push down into SQL. `vfs_metadata` is neither carried on move nor cleaned on delete today. That has to be built
  anyway, and it fixes the same leak for playback positions. The table's stated purpose is plugin and extension
  metadata, not core photo facts.

This is the right choice if the owner reads "no new tables" strictly. The rest of this design works the same on
either option.

### Option C: XMP sidecar files beside the photo

<!-- cspell:ignore Lightroom darktable digiKam digi -->

Write `IMG_0042.jpg.xmp` next to the photo, holding `exif:DateTimeOriginal`, `exif:OffsetTimeOriginal` and the
GPS tags, or an explicit "location removed" marker. Lightroom, darktable and digiKam use this format.

- **For:** no database state at all. The edit travels with the photo through a drive backup, a copy to another
  machine, and other tools that read XMP.
- **Against:**
  - **Clutter.** Every edited photo gains a visible file in Files, which the audience will not understand. Hiding
    `.xmp` means filtering them out of every listing and search, and out of the file index.
  - **Moves.** Every move, rename, copy, trash, restore and delete in `fileutil` has to move the pair together,
    including moves across devices. A move done outside Quark (SMB, a laptop) orphans the sidecar.
  - **Read-only drives.** A photo on a read-only drive cannot be edited at all.
  - **Speed.** A 200-photo shift becomes 200 file writes with no transaction.
  - **Still needs an index.** Sort, month headers and the map cannot open hundreds of sidecars per listing, so
    `photo_hashes` must cache the sidecar value as well. That brings back a database copy with a staleness
    problem.
  - **Dependencies.** Quark has no XMP reader or writer today, so this means a new dependency or a hand-rolled
    one.
  - **"Removed" has no standard form.** XMP cannot say "removed" in a way other tools honor. They fall back to
    the file's GPS, which is the exact privacy failure #4175 is about.

## How an edit reaches sort, search and the map

The rule is one sentence: **the effective value is the override when there is one, and otherwise the value read
from the file.** It is computed in one place on the server, so no client ever merges.

- **Library index stays a pure cache.** `photo_hashes.taken_at`, `latitude` and `longitude` keep holding what
  the file says. The EXIF pass and backfill never read or write overrides. That is what lets them be dropped and
  re-read freely.
- **Taken sort and month headers.** `photoutil.TakenDates` returns the effective date by joining `photo_edits`
  (`COALESCE(e.taken_at, h.taken_at)`). Because `fillTakenDates` already goes through `TakenDates`, the photo
  grid, albums, favorites, name search ordering (JN-PH-023) and `/frame order=newest` all follow without
  separate changes.
- **Locations view (#4279).** `ListPhotoLocations` joins the same way. A `removed` edit excludes the photo even
  though `photo_hashes` holds its GPS. A `set` edit places a photo that has no GPS. The located, unlocated and
  pending counts count the effective value.
- **Info panel.** `GET /photos/metadata` returns the effective date and location, plus an `original` block (the
  EXIF values) and an `edited` flag for each, so the panel can show "Camera said 13:02".
- **Later consumers** — #3496 date and place filters, trips, and the "strip location on download" ticket — read
  the effective value through the same query or helper, never `photo_hashes` directly. The implementing PR adds a
  short comment on the location and date columns saying so.
- **Time zones.** `taken_at` stays an instant (UTC), as today. The offset is used only for display ("14:02 ·
  UTC+1") and for the Time zone tab's arithmetic. The sort key does not change meaning, so unedited libraries
  sort exactly as before. Reading `OffsetTimeOriginal` for unedited photos is a small follow-up to
  `DecodeExif`. It improves display, not order.
- **Events.** One edit request publishes one new `photos_changed` event (photos only, with the device serial).
  The photos page already reloads on file events (JN-PH-024). It treats this one the same way, so 200 photos
  reload open grids once.

## Move, copy and delete

- **Move and rename:** `movePhotoRows` gains `MovePhotoEdits` and `DeletePhotoEditsUnder` beside the favorites
  and album calls, prefix-matched so a moved folder takes its photos' edits along. A cross-device move carries
  them too, as favorites do.
- **Delete:** `DeleteFiles` gains `DeletePhotoEditsUnder` beside the rotation cleanup.
- **Trash and restore:** to decide (see Open questions). Favorites today do not survive a trash and restore. For
  consistency, edits would not either.
- **Copy** (JN-PH-015, Make copies): the copy is a new photo and starts from its own EXIF. The edit is not
  copied. Open question below.

## API

Two routes, one handler file each under `internal/server/api/v0/photos/`. The service functions go in
`photoutil` with the Params/Result pattern. Both take a list of photos, so one photo and a selection are the same
call.

### `POST /api/v0/photos/date`

```json
{
  "photos": [{ "serial": "", "relPath": "Trips/2024/IMG_0042.jpg" }],
  "action": "shift",
  "shiftSeconds": 3600
}
```

`action` is exactly one of:

| action    | fields                           | meaning                                                         |
| --------- | -------------------------------- | --------------------------------------------------------------- |
| `set`     | `takenAt` (RFC 3339 with offset) | every photo gets this date; the server adds the index in seconds |
| `shift`   | `shiftSeconds`                   | effective date + n seconds, offset unchanged                     |
| `zone`    | `offsetMinutes`                  | keep the instant's wall clock, change the offset (a shift)       |
| `revert`  | —                                | drop the date edit                                               |
| `restore` | `previous` (from a response)     | put back each photo's prior edit or no edit, used by Undo        |

A photo with no date at all cannot be shifted. That photo comes back in `skipped` with the reason `no_date`, and
the rest still apply.

### `POST /api/v0/photos/location`

Takes the same `photos` list. The `action` is `set` (`latitude`, `longitude`), `remove`, `revert`, or
`restore`. Coordinates are validated: latitude within ±90, longitude within ±180, and 0,0 is refused because the
index treats it as "no GPS". The route returns 404 when location is off for the account (#3572 and #4277).

### Response (both)

```json
{
  "changed": 36,
  "skipped": [{ "serial": "", "relPath": "scan_001.jpg", "reason": "no_date" }],
  "previous": [{ "serial": "", "relPath": "Trips/2024/IMG_0042.jpg", "edit": null }]
}
```

`previous` is what Undo sends back as `restore`. Undo needs no server-side history table, and an undo of a shift
or a revert is exact.

### Rules

- **Access is all-or-nothing.** Every photo is checked with `accessutil.Write` first, as rotate does. A photo
  that cannot be read is a 404. Any read-only photo makes the whole request a 403, which names the photos. The
  client already knows which selected photos are writable and never sends those. A partial write would make
  Undo's `previous` list misleading.
- **One transaction** per request, on both engines.
- **A size cap** of, say, 5,000 photos per request, so one request cannot hold a write transaction open for
  long. Past that the client splits the request.
- **Swagger annotations** on both routes, `/// api:` tags on the new service methods, and a structural
  change to `GET /photos/metadata` (the `original` and `edited` fields). Per AGENTS.md, that ships as a stack:
  backend PR first, frontend PR above it.

## Writing the date into a downloaded copy

#4174 asks for an optional **Write the date into the file** on download or export. Recommendation: **later**,
as its own ticket. It needs an EXIF writer on a streamed copy, exiftool through `HostPather` on a staged copy or
a Go writer, and that is a separate piece of work. The sibling "strip location on download" ticket needs the same
machinery, so the two belong together.

## Recommendation

Build **Option A**, per-photo (not per-account), with the effective value computed by a server-side join. Ship
it as one stack:

1. `photo_edits` migration pair, queries, `photoutil` service, move and delete bookkeeping, the
   `TakenDates` and `ListPhotoLocations` joins, and the two routes. Go tests on SQLite and PostgreSQL.
2. Frontend: info panel rows and editors, selection bar actions, Undo snack bar, controller tests, and two new
   journeys in `docs/user-journeys/photos.md` (edit a photo's date; edit or remove a photo's location).

Location (#4175) waits on #3572. The table can carry the location columns from day one either way, so the
stack does not have to be redone.

## Open questions for the owner

1. **Strict "no new tables"?** If yes, take Option B (`vfs_metadata` keys) and give up SQL-side date filtering
   for #3496. If a new table is acceptable when justified, take Option A.
2. **Per-photo is assumed.** Both tickets recommend it: anyone who can open the photo sees the corrected date,
   and only a writer can change it. Confirm.
3. **Sort by instant or by wall clock?** This design keeps today's instant ordering. Photos from a trip across
   zones then interleave by real time, which is what most libraries do. The alternative sorts by local wall
   clock.
4. **Trash and restore:** should edits survive a restore from the trash? Favorites do not today.
5. **Make copies:** should a copy carry the original's edits?
6. **Rotation on move:** `movePhotoRows` does not carry `photo_rotations`, so a rotated photo loses its rotation
   when moved. Fix that alongside this work, or file it on its own?
7. **Write into the file on export:** confirm it is deferred to a ticket shared with "strip location on
   download".
8. **#3572's outcome** settles whether the location half ships at all, and whether location edits follow the
   per-account map opt-in (#4277) or a Quark-wide setting.
