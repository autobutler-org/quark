# Photo media type views

**Status: Proposed.** Nothing here is built. Covers #4178 (ready-made views by kind of media: videos, Live
Photos, screenshots, RAW, panoramas, selfies, slow motion). The open questions at the end need the owner's answer
before the ticket is ready to work.

## The problem

A household library mixes every kind of picture a phone makes. Someone looking for "that slow-motion video of the
dog" or "the panorama from the lake" has to scroll the whole timeline. Phones answer this with fixed views by kind
of media. Quark has the facts to do the same without looking at a single pixel: the file name, the file type, and
the camera's own notes in the file's headers.

The ticket asks for seven views, listed under a **Media types** heading in the album sidebar, each shown only when
it has something in it. They are fixed views, not rules the person writes. #3570 (rule-based collections) has a
**Screenshots** preset and #3500 (cleanup review) also looks for screenshots, so "screenshot" has to mean the same
thing in all three places.

## What exists today

- **Listing.** `photoutil.ListPhotos` (`pkg/util/photoutil/list.go`) walks the library, through the in-memory file
  index when one is built, and keeps `image/*` files. With `IncludeVideos` it lists videos too, each with
  `IsVideo` and `DurationMs` (#3428). The backend half of #3428 has landed. The app does not pass
  `includeVideos=true` yet, so videos still do not show in Photos, and JN-PH-017 still says video files are not
  photos.
- **Live Photos.** The same walk pairs `IMG_1.HEIC` with `IMG_1.MOV` and sets `HasLiveVideo`. The companion clip is
  never listed on its own.
- **Headers.** `ExifData` (`pkg/util/photoutil/photoutil.go`) has `LensModel`, `Width` and `Height`. It does not
  read XMP `GPano` tags or EXIF `UserComment`. `videoutil.ProbeSource` already returns a video's `Framerate` from
  its container header, with no decoding.
- **The library index.** `photo_hashes` holds one row per library photo: hashes, `taken_at` and `taken_checked`
  (migration 020). It is a **cache** of what the file says. The backfill (`backfill.go`) fills it in the
  background, and a move or delete drops the row. Videos have no row today.
- **Sidebar.** `PhotoLibrarySidebar` and `PhotoCategoryList` in `packages/quark_widgets/lib/src/photos/`. An album
  is opened by URL, `/photos?album=<link>`.

## How each view decides

Every rule reads only the file name, the file type, and headers. Nothing is recognized from the picture.

| View | Rule | Needs headers? |
| --- | --- | --- |
| **Videos** | file type `video/*`, not a Live Photo's companion | no |
| **Live Photos** | `HasLiveVideo` | no |
| **RAW** | `storageutil.IsRawImageExtension`, the RAW list Quark already keeps | no |
| **Screenshots** | the file name says so (`Screenshot`, `Screen Shot`, `Screenshot_`), **or** a PNG whose size matches a phone screen, **or** iOS's `UserComment` "Screenshot" | name: no; size and comment: yes |
| **Panoramas** | XMP `GPano` tags, **or** the long side at least twice the short side and wider than 4,000 pixels | yes |
| **Selfies** | `LensModel` names a front camera ("front camera", "FaceTime") | yes |
| **Slow motion** | a video whose container says 120 frames per second or more | yes (video header) |

Two notes on the rules:

- **Panoramas** use the long side over the short side, so a panorama shot holding the phone upright counts too. The
  4,000-pixel floor keeps a cropped banner image or a wide screenshot out.
- **Selfies** are the weakest rule. iPhones write "front camera" into `LensModel`; many Android phones write nothing
  there. The view would show iPhone selfies and miss most Android ones. See Open questions.

### One matcher, three callers

The rules live in one place, `photoutil.MediaKinds(name, mimeType, exif) MediaKind`, returning a bit set. #3570's
Screenshots preset and #3500's cleanup queue call the same function, so a screenshot is the same file everywhere.
The function takes values already read, never a path, so it is a pure function with a table test per rule.

## Where the kinds are stored

The ticket requires that opening a view does not decode every file. Four of the seven kinds need only the name and
type, which the listing walk already has in memory. The other three need a header read once per file.

### Option A: a `media_kinds` column on `photo_hashes` (recommended)

Add one integer column, a bit set, to the existing table, filled by the backfill pass that already reads each
photo's EXIF for `taken_at`. Videos gain a row too, with null hashes, so the backfill can store the slow-motion bit
from `ProbeSource`. Kinds that need no header (Videos, Live Photos, RAW, a screenshot by name) are computed by the
walk itself and never stored, so a rename is right the moment it happens.

- **For:** no new table. The kinds are derived from the file, so they belong in a cache that can be dropped and
  re-read, which is exactly what `photo_hashes` is. The move and delete bookkeeping already exists. A count per
  kind is one `GROUP BY` filtered by the photos the walk kept.
- **Against:** video rows in a table named for photo hashes. Duplicate detection reads only rows with a hash, so
  the video rows do not disturb it, but the implementing PR adds a test that says so. A migration clears
  `taken_checked` so the backfill reads every photo once more.

### Option B: a separate `photo_media_kinds` table

The same bit set in a table of its own, keyed by `(device_serial, rel_path)`.

- **For:** keeps `photo_hashes` about images.
- **Against:** a second table with the same key, the same lifetime and the same move and delete code as
  `photo_hashes`, for one integer. AGENTS.md says to add tables only as a last resort, and this is not one.

### Option C: nothing stored, read headers on demand

Compute every kind during the walk, reading headers for the three that need them.

- **Against:** the ticket rules it out. A library of 50,000 photos would read 50,000 headers to open
  **Panoramas**.

## API

- **`GET /api/v0/photos?kind=<kind>`** filters the existing listing: `videos`, `live`, `screenshots`, `raw`,
  `panoramas`, `selfies`, `slow-motion`. Sort, paging, search (`q`) and the access filter work unchanged. `kind=videos`
  and `kind=slow-motion` imply `includeVideos=true`.
- **`GET /api/v0/photos/kinds`** returns a count per kind for the calling account, counting only photos it can
  read. The sidebar lists the kinds with a count above zero. A photo whose headers are not read yet is not counted
  under a header kind; the response carries `pending`, as `pendingDates` does today, so the app can say the views
  are still filling in.
- Swagger annotations and `/// api:` tags as usual. The listing gains a query parameter and a new route, which per
  AGENTS.md ships as a stack: backend first, frontend above it.

## Frontend

- **Sidebar.** A **Media types** section under the albums, built as a new package widget, `PhotoMediaTypeList`
  (keys `photo_media_type_<kind>`), fed the counts from the controller. It follows the albums list's collapse
  behavior (JN-PH-025).
- **Phone.** The same entries go in the library picker in the bar, under their own heading.
- **URL.** A view is `/photos?view=<kind>`, beside `?album=`, so reload and a shared link keep it.
- **Copy.** The labels are the ones above: **Videos**, **Live Photos**, **Screenshots**, **RAW**, **Panoramas**,
  **Selfies**, **Slow motion**. RAW is the word camera owners use; it stays. While headers are still being read,
  the section shows "Still sorting some photos" under the heading.
- **Videos in the grid.** A video tile shows its length, and opening it plays it, which #3428 brings.

## Videos in Photos at all

The ticket's first decision. **Recommendation: videos join the main timeline**, as on every phone. The backend is
ready (#3428); the app needs to pass `includeVideos=true`, show a duration on the tile, and open the video player.
JN-PH-017 then changes to say that a dropped video uploads too. That is #3428's frontend work, and **Videos** and
**Slow motion** stack on it. If the owner wants videos kept out of the timeline, the **Videos** view still works,
and is then the only place they show.

## Stacking

- **After #3428's frontend** (videos in the grid), unless the owner keeps videos out of the timeline. The matcher
  and the storage do not wait on it; only **Videos** and **Slow motion** in the sidebar do.
- **On the existing backfill** (`BackfillHashes`, `backfillTakenAt` in `backfill.go`), which gains one more value to
  store per photo. No other photo index work has to land first.
- **Under #3570 and #3500.** Their Screenshots preset and cleanup queue call `MediaKinds` rather than writing their
  own rules, so whichever of them is built after the matcher ticket reuses it.

## Proposed tickets

Each is one reviewable PR.

1. **backend: the media kind matcher.** `photoutil.MediaKinds`, `ExifData` gains `UserComment` and the `GPano`
   flag, table tests with fixture files for every rule. No storage, no route. **Difficulty: standard.**
2. **backend: store and serve kinds.** Migration pair adding `media_kinds` to `photo_hashes` on SQLite and
   PostgreSQL, video rows from the backfill with the frame rate, `kind=` on the listing, `GET /photos/kinds`, Go
   tests on both engines. **Difficulty: standard.**
3. **frontend: Media types in the sidebar.** `PhotoMediaTypeList` with tests at 360x640 and 1280x800 and a
   gallery entry, the controller and the `?view=` route, the phone picker entries, and a new journey in
   `docs/user-journeys/photos.md`. Stacked on 2. **Difficulty: standard.**

## Open questions for the owner

1. **Proposed: videos join the main timeline.** Confirm, or keep them only in the **Videos** view.
2. **Proposed: a column on `photo_hashes`**, with video rows in it, rather than a new table. Confirm.
3. **Proposed: ship Selfies with the iPhone-only rule**, and hide the view when nothing matches, which on an
   Android-only household is always. The alternative is to leave Selfies out until a better signal turns up.
4. **Proposed: a panorama is 2:1 or wider and over 4,000 pixels on its long side.** Confirm the threshold.
5. **Proposed: a screenshot by size alone** counts only for PNGs. A JPEG at exactly a phone's screen size is more
   often a saved image than a screenshot. Confirm.
