# Live Photo key frame

**Status: Proposed.** Nothing here is built. Covers #4159 (choose which frame of a Live Photo is the photo everyone
sees, by dragging through its frames). The picker's layout, states, keys and copy are already designed in the
ticket's comments and are not repeated here. This document settles what the ticket left open: who renders the
frame, where the choice is stored, and how it reaches every screen. The open questions at the end need the
owner's answer before the ticket is ready to work.

## The problem

A Live Photo is a still and a three-second clip. The camera picks the still, and sometimes it picks the moment a
child blinked. iPhone Photos lets a person drag through the clip and make any frame the photo. Quark should too,
without changing either original file: a photo's hash has to stay stable for phone backup and duplicate detection.

## Decisions already made

The owner settled these on 2026-11-14, in the ticket:

- The Quark records the chosen frame, as its time in the clip. The photo and the clip are never rewritten.
- The client renders the frame, because the Quark has no decoder for the clip, and uploads the still. The grid
  and viewer show that still.
- **Anyone who can see the photo can choose a key frame for themselves.** The choice of someone who can change the
  photo is what everyone else sees, unless they have chosen their own. This replaces the ticket body's "needs write
  access".
- The choice has to survive a restore. When #4214 (library export) has merged, key frames join the export in the
  same PR; if this lands first, #4214's table classification test picks the data up.

## What exists today

- **Pairing.** `photoutil.ListPhotos` pairs `IMG_1.HEIC` with `IMG_1.MOV` by name and sets `HasLiveVideo`
  (`pkg/util/photoutil/list.go`).
- **No video decoding on the Quark.** #2378 removed ffmpeg. `thumbnailutil` decodes a keyframe only out of AV1 and
  VP8, and Live Photo clips are HEVC or H.264, so the Quark cannot cut a frame out of the MOV.
- **Client thumbnails.** `uploadutil.Sidecars.Attach` stores a JPEG a client sends beside an upload, checked as a
  JPEG and capped at 1,024 pixels on its long side (`thumbnailutil/client.go`). That cap is too small for the
  viewer, and the path only runs during an upload.
- **Rotation is the precedent.** `photo_rotations` is a per-photo, non-destructive edit on the server. The listing
  sends `rotationQuarters`, and the client puts it in the thumbnail URL so a rotated photo gets a fresh thumbnail.
  `movePhotoRows` carries it on move, and `DeleteFiles` drops it.
- **Frame rate.** `videoutil.ProbeSource` reads a clip's frame rate from its header, which the picker snaps to.
- **Playback** of a Live Photo is #4158, in progress separately.

## Rendering the frame

The web and the phones differ.

- **Web:** seek the paused `<video>` to the chosen time and draw it into a canvas, then encode a JPEG. No new
  code beyond the app.
- **iOS and Android:** `video_player` has no way to grab a frame. Three options:
  1. **A small platform channel** in the app: `AVAssetImageGenerator` on iOS, `MediaMetadataRetriever.getFrameAtTime`
     on Android, each a few dozen lines. No new dependency. **Recommended.**
  2. **A frame-grab plugin from pub.dev.** Less code of our own, but a new dependency, which AGENTS.md says to ask
     about first, and most such plugins are thinly maintained.
  3. **Decode on the Quark.** Rejected: it brings back the video decoder #2378 removed.

The same channel draws the strip's frame tiles, so the picker and the save share one code path per platform.

## Where the choice is stored

Two things are stored per choice: the **time in the clip** (to put the handle back and mark the current key photo)
and the **rendered JPEG**. The JPEG cannot be made again on the Quark, so it is not a cache: losing it loses the
person's choice. It has to be kept with the same care as the time, and backed up with it.

### Option A: a `photo_key_frames` table plus JPEG files in the data directory (recommended)

```sql
CREATE TABLE photo_key_frames (
    device_serial TEXT    NOT NULL DEFAULT '',
    rel_path      TEXT    NOT NULL,
    account_id    INTEGER NOT NULL DEFAULT 0,  -- 0: the shared choice, made by someone who can change the photo
    offset_ms     INTEGER NOT NULL,
    updated_at    DATETIME NOT NULL,
    PRIMARY KEY (device_serial, rel_path, account_id)
);
```

The JPEG goes to `<data>/key-frames/<id>.jpg`, outside the user's folders and outside the thumbnail cache, named by
a random id the row could carry, or by a hash of the row's key. Thumbnails of every size are resized from it by
the existing generator, the way client thumbnails are.

- **For:** it follows rotation, favorites and album items exactly: keyed by path, carried by `movePhotoRows`,
  dropped by `DeleteFiles`, in one place with them. A listing loads every key frame for the account in one query,
  the way it loads rotations. The owner's note that #4214's table classification test "picks the new data up"
  assumes a table.
- **Against:** a new table and a migration pair, for what will be a few rows in most homes. The table and the JPEG
  files must agree, so a restore has to bring back both.

**Why the database is justified here.** The choice is user-made state that by decision cannot go in the photo, it
is read on every listing to name the thumbnail, and it is per account as well as per photo. Every other per-photo
choice Quark keeps (rotation, favorites, album items) is already a row, and a second bookkeeping path beside
`movePhotoRows` would be the one that gets forgotten.

### Option B: JPEG files only, no table

Put everything in the file name: `<data>/key-frames/<serial>/<hash of rel path>/<account>.<offset ms>.jpg`. The
Quark builds a small in-memory index of the directory at startup.

- **For:** no table. One kind of thing to back up.
- **Against:** a move or delete has to rename or remove files in step with `movePhotoRows`, through new `os` code
  that `scripts/check-go-structure.bash` has to allow, with no transaction tying it to the rows that move beside
  it. #4214's export is built around tables and would need a file case. The in-memory index is a second source of
  truth to keep fresh across instances (#3083's reason the settings left a file).

### Option C: keys in `vfs_metadata`

The time as a `photos.keyFrame` key (or `photos.keyFrame.<account>`) on the photo's path, plus the JPEG files.

- **For:** no new table.
- **Against:** `vfs_metadata` is neither carried on move nor cleaned on delete today (see `photo-metadata-edits.md`),
  its values are JSON sqlc cannot check, and its stated purpose is plugin metadata. The same choice is open there as
  question 1; this should follow whatever the owner answers.

### Not considered further

A sidecar file beside the photo in the user's folder. It clutters Files, breaks on moves done outside Quark, and
fails on a read-only drive.

## How a key frame reaches every screen

- **Listing.** Each Live Photo with a key frame gains `keyFrameMs`: the account's own choice if it has one,
  otherwise the shared choice. The client puts it in the thumbnail URL beside `rotationQuarters`, so the cached
  thumbnail changes when the choice does.
- **Thumbnails and the viewer.** The thumbnail route and the full-size image route serve the key-frame JPEG when
  the account has one in effect. Downloads still serve the original file.
- **`/frame`.** The slideshow has no account choice of its own; it uses the shared choice.
- **Duplicates.** Hashes stay those of the original file, so duplicate detection is unchanged. The duplicates page
  shows the key frame as the picture.
- **Rotation** applies on top of the key frame, as it does to the still.
- **Events.** A save publishes an event for the photo's path through `deps.EventBus()`, so other open clients reload the
  tile. A personal choice is delivered only to that account.

## API

- **`PUT /api/v0/photos/key-frame`**, multipart: `serial`, `relPath`, `offsetMs`, `scope` (`mine` or `everyone`),
  and an `image` part holding the JPEG. The image is read through `io.LimitReader` with a cap (say 20 MB), checked as
  a JPEG whose dimensions match the photo's within a few pixels, and streamed to disk. `scope=everyone` needs write
  access to the photo (`accessutil.Write`); `scope=mine` needs read.
- **`DELETE /api/v0/photos/key-frame`** with `serial`, `relPath`, `scope`: **Reset to original**. Resetting your
  own choice falls back to the shared one; resetting the shared one needs write.
- **`GET /photos/metadata`** gains the key frame in effect, whose choice it is, and the shared one, so the picker
  can place both markers.
- Swagger, `/// api:` tags, and a structural change to the listing, so this ships as a stack: backend first,
  frontend above it.

## Frontend

The ticket's design comment is the spec: the `LiveFrameStrip` package widget, its keys, states, reduced-motion
rules and copy. Two additions follow from the decisions:

- **Who sees the change.** Someone who can change the photo sees **Make key photo for everyone** as the main
  button and **Just for me** beside it. Someone who can only see it gets **Make key photo**, which saves for them
  alone, and a line under it: "Only you will see this frame."
- **Undo.** The snack bar's **Undo** puts back the previous choice, which may be no choice.

## Stacking

- **After #4158** (Live Photo playback), whose paused-motion view the picker scrubs.
- **Beside #4214.** Either order; see Decisions already made.
- **Shares the platform channel** with any later **Save as photo** (#3571), which writes the same frame as a new
  JPEG in the person's folder.

## Proposed tickets

Each is one reviewable PR.

1. **backend: store and serve key frames.** Migration pair on SQLite and PostgreSQL, sqlc queries, the JPEG store,
   `PUT` and `DELETE` routes, `keyFrameMs` on the listing, the thumbnail and image routes serving the key frame,
   move and delete bookkeeping, and integration tests including "the original files hash the same before and
   after". **Difficulty: standard.**
2. **mobile: frame grab channel.** The iOS and Android platform channel with a Dart API and a web implementation
   behind a conditional import. **Difficulty: standard.**
3. **package: `LiveFrameStrip`.** The widget, tests at 360x640 and 1280x800, a reduced-motion test, and the
   gallery entry. **Difficulty: standard.**
4. **frontend: Choose key photo.** The viewer menu item, the picker page section and controller, save and reset,
   and a new journey in `docs/user-journeys/photos.md`. Stacked on 1, 2 and 3. **Difficulty: standard.**

## Open questions for the owner

1. **Proposed: Option A**, a `photo_key_frames` table with the JPEGs in the data directory. If the answer to
   question 1 of `photo-metadata-edits.md` is "no new tables", this follows it to Option C.
2. **Proposed: a platform channel** for the frame grab on iOS and Android, not a new plugin. Confirm.
3. **Proposed: downloads stay the original file.** A later **Save as photo** writes the frame as a new JPEG.
   Confirm, as the ticket proposed.
4. **Proposed: a writer chooses "for everyone" or "just for me"**, and a reader always "just for me". Should a
   writer's choice instead always be for everyone, with no "just for me"?
5. **Proposed: Android motion photos (#3502) are out of scope** until they are paired the way Live Photos are.
   Confirm.
