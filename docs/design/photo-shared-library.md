# Household shared library

**Status: Proposed.** Nothing here is built. Covers #4181 (several accounts pool photos into one library). The
open questions at the end need the owner's answer before the ticket is ready to work.

## The problem

Two parents each back up their phone to the Quark. Each sees their own photos and whatever folder the other has
shared with them. What they want is one family library: every photo either of them chose to share, in one
timeline, with no thought about folders. Each person still keeps photos that are theirs alone.

The ticket asks for:

- one pool every member sees in full, mixed into their Photos or as a separate **Shared library** view;
- a switch on each phone saying whether its new photos go to the shared library or stay personal;
- moving any photo in or out later;
- albums and favorites unchanged, still per account.

## What exists today

- **Groups have folders.** Every group has `groups/<name>` on the internal drive, which the group can write to
  (`pkg/util/grouputil`, #2016). It is made with the group, moves on rename, and stays (admin-only) when the
  group is deleted.
- **Photos already lists everything an account can read.** `photoutil.ListPhotos` walks every device and drops
  what `accessutil` says the account cannot read. A photo in a folder shared with you is already in your All
  photos timeline today.
- **Moves carry per-photo state.** `movePhotoRows` (`pkg/util/fileutil/helpers.go`) carries favorites, album items
  and rotation to a moved file.
- **Trash is per item, with who trashed it.** `accessutil.CanSeeTrash` shows a trashed item to whoever trashed it
  and to anyone who can read where it came from. `CanDeleteTrash` lets anyone who can write that folder empty it
  for good.
- **Settings.** Quark-wide values are rows in the existing `settings` table (`settingsutil`); per-account values
  are in `user_settings` (`usersettingsutil`). Neither needs a migration for a new key.
- **Phone backup** (#285, slices #4160–#4170) lands photos in `<home>/Phone backup/<phone name>/<YYYY>/<MM>/`.
- **Album sharing** (#1952) is open and undecided.

## Options

### Option A: a group folder plus a Photos view over it (recommended)

The shared library **is** a folder: `groups/<household>/Shared library/`, owned by a group the admin picks (the
built-in **everyone** group in most homes). Being in the group is being in the library. Photos gets a
**Shared library** view that lists only the photos under that folder.

- **For:** it is what Quark already has. Access, trash, moves, events, backups, the file index and the Files page
  all work on it with no new code. Every photo stays a file, visible in Files and copyable off the drive. No new
  table: the one new fact, "this group folder is the shared library", is one row in `settings`.
- **Against:** the shared library lives on the internal drive. A photo on a USB drive moves across devices to
  join it. A household that wants two separate pools (grandparents and the kids) would need a second group, which
  this design does not offer at first.

### Option B: a "shared" mark on each photo, files left where they are

A new table lists which photos are in the shared library, wherever they sit. Members see a photo through the mark,
not through folder access.

- **For:** adding a photo is instant, with no file moving, and a photo can stay in its owner's folder layout.
- **Against:** it is a second access model beside `accessutil`. Every place that checks whether an account may
  read a file (thumbnails, downloads, `/frame`, search, the viewer, events) would have to learn about the mark, and
  a missed one leaks a photo. The other member cannot see the photo in Files, which is confusing. It is a new table
  for state the file layout already expresses. Not recommended.

### Option C: a shared album holding everything

Build on #1952 and make the shared library an album every member can add to.

- **Against:** an album is a curated list of pointers, not "everything". The phone's switch would add album rows
  for every backed-up photo, and the photos would still need folder access to be readable. It inherits every open
  question in #1952. Not recommended.

## Recommendation

Option A. The shared library is a group folder. Photos and the phone backup learn where it is; everything else is
file sharing Quark already does.

## User flow

The audience is a household, not an administrator. Nobody should meet the words "group" or "folder" to use this.

- **Turning it on.** In Settings, an admin (usually whoever set up the Quark) sees **Shared library** with **Turn
  on**. It says "Everyone on this Quark can add photos to one family library and see everything in it. Each
  person's other photos stay private." Turning it on uses the **everyone** group; **Choose who** lets the admin pick
  another group instead.
- **Seeing it.** Photos gets a **Shared library** entry at the top of the sidebar, under **All photos**, and the
  same entry in the phone's library picker. **All photos** keeps showing everything the person can see, the shared
  library included, which is what it does today.
- **The phone switch.** In the phone backup settings: **Add new photos from this phone to the shared library**,
  off by default. When on, backed-up photos land in `Shared library/Phone backup/<phone name>/<YYYY>/<MM>/` rather
  than the person's home.
- **Moving in.** A selection (JN-PH-027) or the viewer's More menu gets **Add to shared library**. The photo
  moves into `Shared library/<YYYY>/<MM>/`, by capture date, or by date added when there is none. A clashing name
  gets ` (1)`.
- **Moving out.** **Remove from shared library** moves the photo to the person's home, into
  `Photos/<YYYY>/<MM>/`. Only someone who can write the shared library sees it, which in Option A is every member.
- **A badge.** In **All photos**, a shared-library photo carries a small two-people mark in its corner, so a person
  can tell at a glance what the family sees.
- **Deleting.** A member who deletes a shared photo puts it in the trash. Every member sees it there and can
  restore it, because they can read where it came from.

## Data and schema

**No new table.**

- **Settings:** one row in `settings`, `photos.sharedLibrary`, holding the group id and the folder path. Unset
  means the feature is off.
- **The phone switch:** the phone's own setting, stored with the other backup options on the phone, sent as the
  destination of each upload. The Quark does not need to remember it.
- **The photos:** files in the group folder. Favorites, album items and rotation are already keyed by path and
  carried by `movePhotoRows`.
- **Backups:** the folder is user files, so drive backups cover it. The setting row goes into #4214's export
  with the other settings.

## API

- **`GET /api/v0/photos?under=shared`** filters the existing listing to the shared library. Sort, paging, search
  and media type views (see `photo-media-views.md`) compose with it. Each listed photo gains `inSharedLibrary` for
  the badge.
- **`POST /api/v0/photos/shared-library`** moves a list of photos in or out: `{"photos": [...], "action": "add" |
  "remove"}`. It runs the existing `fileutil` move per photo, so access checks, bookkeeping and events are the
  ones every move gets. The response lists each photo's new path and any that were skipped, with a reason
  (`read_only`, `already_there`).
- **`GET` and `PUT /api/v0/settings/shared-library`** (admin only for `PUT`) read and set the group. Turning it on
  creates the folder through `grouputil` and grants the group write.
- **Phone backup** asks the Quark for the destination folder; the shared library is one more answer.
- **Dedup across members.** #285's "already on the Quark" check asks for hashes the account holds. It must also
  count photos in the shared library, or one parent's phone re-uploads a photo the other already shared. That
  check runs over the files the account can read, so it holds once the library is readable.

Swagger and `/// api:` tags as usual, stacked backend-first per AGENTS.md.

## Stacking

- **After #285's destination slice.** The phone switch is one more destination; the rest of this does not wait for
  phone backup.
- **Not on #1952.** The ticket lists album sharing as a dependency for "the sharing semantics". Option A uses
  folder sharing instead, so it does not need #1952 and the blocked-by link can come off. The two stay
  complementary: a shared album is a hand-picked set, the shared library is everything.
- **Beside `photo-media-views.md`.** Both add a filter to the same listing; whichever lands second composes with
  the first.

## Proposed tickets

Each is one reviewable PR.

1. **backend: the shared library setting and folder.** The `settings` row, `GET`/`PUT` route, folder creation and
   grant through `grouputil`, and Go tests. **Difficulty: standard.**
2. **backend: list and move.** `under=shared` and `inSharedLibrary` on the listing, the add/remove route over
   `fileutil` moves, and integration tests with two accounts: each sees what the other added, neither sees the
   other's personal photos, albums and favorites survive a move in and out. **Difficulty: standard.**
3. **frontend: Shared library in Photos.** Settings section, sidebar and picker entry, the badge, selection and
   viewer actions, controller tests, and a new journey in `docs/user-journeys/photos.md`. Stacked on 1 and 2.
   **Difficulty: standard.**
4. **mobile: back up to the shared library.** The per-phone switch and destination. Stacked on #285's destination
   slice. **Difficulty: standard.**

## Open questions for the owner

1. **Proposed: Option A**, the shared library is a group folder, with no new table. Confirm.
2. **Proposed: one shared library per Quark**, on the **everyone** group unless the admin picks another. Is a
   second pool (a second group) needed at first?
3. **Proposed: adding a photo moves the file** (one copy). Removing it moves it to the person's
   `Photos/<YYYY>/<MM>/`. Confirm both, or should **Remove** put it back where it came from, which needs the
   origin remembered?
4. **Proposed: any member can delete a shared photo**, with the trash as the safety net, since every member can
   restore it. The alternative, only the person who added it, needs a record of who added what, which files do not
   carry.
5. **Proposed: favorites stay per account**, even on shared photos. Confirm.
6. **Proposed: no Personal-only view.** **All photos** shows both, **Shared library** shows the pool. Is a "Mine
   only" view wanted?
7. **Proposed: drop #1952 as a blocker** of #4181.
8. **What happens when someone leaves the group?** They lose read on the folder, so the shared photos drop out of
   their timeline and albums. Photos they added stay in the library. Confirm that is the intent.
