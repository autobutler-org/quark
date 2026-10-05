# File version history

Version history (#1173) keeps earlier copies of a file so a user can look back at one and put it back. It is
generic: any file on the internal device can carry versions. The slide, sheet and doc editors are the first to
use it, and they get automatic snapshots on save. `pkg/util/fileversionutil` holds the logic, and
`internal/server/api/v0/versions/` serves it at `/api/v0/versions`.

## What is stored, and where

A file's versions sit in a hidden store beside it, one directory per file:

```text
Documents/
  pitch.qslide                         ← the file
  .quark-versions/
    pitch.qslide/
      index.json                       ← what the store holds
      20261005T101530Z-3f9a0c1d.snap   ← one snapshot: a byte-for-byte copy
      20261005T114502Z-81be22f0.snap
```

- **A snapshot is a copy of the file's bytes**, streamed with `io.Copy` through `pkg/vfs`. It is never held in
  memory. The `.snap` extension keeps the content search from indexing it as a second copy of the document.
- **`index.json` lists the snapshots**, newest first: `id`, `createdAt`, `size`, `sha256`, `kind` (`auto` or
  `named`), an optional `label`, and `authorId`, the account that made it. It is written through the VFS, so it
  lands with the same atomic temp-then-rename every other write uses. It is read through a 1 MiB limit, and an
  entry whose id is not in the shape the store mints is ignored, so a hand-edited index cannot point outside
  the store.
- **An id is a UTC timestamp plus 8 random hex digits** (`20261005T101530Z-3f9a0c1d`). Ids sort by time, and
  a snapshot's file name is derived from its id and nothing else. An id that does not match that pattern is
  refused before it touches a path, which shuts out traversal through the id (`../x`, `%2e%2e`, and so on).
- **`.quark-versions` is reserved** the way the old `.trash` is: `storageutil.IsInternalName` names it, so the
  listings, the recursive walk, the file-name index, by-type and recent, photos, books and folder zips all skip it.
  Folder sizes still count it, because it takes up real disk space.

## Snapshots

`Snapshot(path, kind, label)` copies the file's current bytes into its store.

- **Dedupe.** A file whose SHA-256 matches the newest snapshot's is not copied again. The call reports the
  existing snapshot with `created: false`.
- **Auto snapshots are rate-limited** to one per file every `AutoSnapshotInterval` (10 minutes, a constant in
  `fileversionutil`). The clock is the newest auto snapshot's `createdAt` in the index, so the limit survives a
  restart and needs no memory state.
- **Named snapshots** carry a label and skip the rate limit. Only named snapshots can be deleted by hand.
- **The save hook.** When the multipart upload overwrites a `.qslide`, `.qsheet` or `.qdoc` on the internal
  device (how all three editors save), the upload snapshots the old content (`auto`) *before* the new bytes
  replace it. So the history holds the states you saved over, and the live file is always the newest state.
  The hook needs no client change. A failed snapshot is logged and never fails the save. Chunked upload
  sessions and serial-addressed devices do not snapshot; the editors use neither.

## Retention

`Prune` runs after every snapshot. It removes auto snapshots only, named ones are kept:

- beyond the newest `MaxAutoVersions` (50),
- older than `MaxAutoAge` (90 days),
- the oldest ones while the store is over `MaxStoreBytes` (256 MiB per file).

A named snapshot that would take the store over `MaxStoreBytes`, even with every auto snapshot gone, is refused
(`413`). Prune writes the index first and deletes `.snap` files after it. A crash in between leaves an
unreferenced `.snap`, never an index entry with no file, and the next prune removes the stray.

## Restore

`Restore(path, id)` puts a snapshot back:

1. Snapshot the current content as `auto`, labeled `Before restore`, bypassing the rate limit (dedupe still
   applies). So every restore can be undone by restoring that snapshot, and restoring a restore works the
   same way.
2. Stream the snapshot over the file through `vfs.Write`. For the `files` namespace that is
   `storageutil.WriteFileAtomic`: a temp file beside the target, fsynced, then renamed over it. A failed or
   interrupted restore leaves the old file whole.
3. Publish `upload` for the file on the event bus, so open clients, the content index and the file-name index see
   the change.

Snapshot, restore, delete and prune for one file run under one lock. The `fileversionutil.Store` on
`deputil.Dependencies` holds a fixed set of striped mutexes, so concurrent saves cannot interleave index
writes.

## Following the file

`Store.Watch` subscribes to the event bus:

- **Rename or move** (`move`, internal device): the store moves from
  `<old dir>/.quark-versions/<old name>` to `<new dir>/.quark-versions/<new name>`. A store already at the
  destination belonged to the file the move replaced, so it is dropped. A folder move needs nothing: its
  `.quark-versions` directories travel inside it.
- **Trash** (`delete`): the store stays where it is, so restoring the file from the trash brings its history
  back. A trashed folder takes its stores into the trash with it.
- **Permanent delete** (`trash_changed`, from emptying the trash, deleting one item, or the 30-day expiry):
  for each folder that has had a delete since startup, a store is removed when its file no longer exists and
  no trash item would restore to that path.

## Failure modes

| What happens                                     | Result                                                                 |
| ------------------------------------------------ | ---------------------------------------------------------------------- |
| Crash mid-snapshot                               | The temp file is discarded; index and file untouched                   |
| Crash between index write and stale `.snap` delete | Stray `.snap`, removed by the next prune                             |
| Crash mid-restore                                | The atomic write leaves the old file; the pre-restore snapshot exists  |
| Snapshot fails during a save                     | Logged; the save goes through without a history entry                  |
| `index.json` corrupt or hand-edited              | Read as empty or filtered to valid entries; the next snapshot rewrites it |
| Events missed (subscriber overflow, restart)     | A store can be left behind at an old path. Moves are not replayed; a store orphaned by a missed event lingers until a later delete in that folder sweeps it |
| Cross-device move                                | History stays on the internal device and is swept once the trash no longer holds the path |

## Access

The caller needs **read** access to a file to list its versions or download one, and **write** access to take a
snapshot, restore, or delete one. This is the same `accessutil` check every file endpoint makes. A file the
caller cannot see answers `404`, one they can see but not change answers `403`. Admin is not required.

| Method   | Route                              | Needs |
| -------- | ---------------------------------- | ----- |
| `POST`   | `/api/v0/versions`                 | write |
| `GET`    | `/api/v0/versions?path=`           | read  |
| `GET`    | `/api/v0/versions/:id/content?path=` | read |
| `POST`   | `/api/v0/versions/:id/restore?path=` | write |
| `DELETE` | `/api/v0/versions/:id?path=`       | write (named versions only) |

## Why not the database

AGENTS.md makes a table the last resort, and nothing here needs one. A snapshot is file content, so it belongs
on disk next to the file it copies, where it shares the file's device, backups, trash and moves. A row would
have to be kept in step with all of those. The index is small and only ever read per file, so a JSON file
beside the snapshots answers every query the API makes. Deleting the store directory removes the history
completely, with nothing left behind in SQLite.
