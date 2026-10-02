# Durability

What survives when the power dies or the device shuts down uncleanly, and why. The bar (#2517) is that software
never quietly corrupts the vault or an upload: a crash may lose work that was still in flight, but nothing
half-written is ever presented as complete, and nothing already acknowledged is lost.

Two failures look alike from outside and are not:

- **A process crash** (a panic, `kill -9`, the OOM killer). The kernel still holds every byte the process wrote,
  and writes it out later. Only the ordering of Quark's own steps matters.
- **A power cut.** Whatever the kernel had not yet written to disk is gone, and it does not go in the order it was
  written: a rename can reach the disk before the bytes of the file it names. Only data that was flushed
  (`fsync`) before the cut is guaranteed to be there.

## SQLite: the main database and the vault

Every database is opened through `db.DSN`, and the driver's defaults stand: a rollback journal
(`journal_mode=DELETE`) with `synchronous=FULL`. SQLite flushes the journal before it touches the database and
flushes the database before it deletes the journal, so a committed transaction survives a power cut and an
uncommitted one is rolled back when the database is next opened. Nothing in Quark changes those settings; do not
switch to WAL or lower `synchronous` without revisiting this page.

| Write                                  | Commit point                                                       |
| -------------------------------------- | ------------------------------------------------------------------ |
| Vault setup                            | one `INSERT` of the config row (salt, verification blob)           |
| Entry and folder create, edit, delete  | one statement each                                                 |
| Master password change                 | one transaction re-encrypts every entry and swaps the config       |
| Vault import                           | one transaction                                                    |
| Moving the vault to another device     | see below                                                          |

Moving the vault (`vaultutil.SetLocation`) spans two databases, so no single transaction covers it. It runs in the
one order every crash point survives: the copy commits on the target (replacing any earlier partial copy), then
the main database records the new location, and only then is the source emptied. A crash before the location
moves leaves the vault where it was; a crash after leaves a stale, still-encrypted copy on the old device, which
the next move onto that device replaces.

## Files

Every write that lands a user file goes through a temp file beside its destination and a rename:

1. Stream the bytes into a temp named with `storageutil.WriteTempPrefix` (listings hide it, #1828).
2. `fsync` the temp.
3. Rename it over the real name, or hard-link it when a taken name must be refused atomically.
4. `fsync` the directory, so the new name itself survives.

`storageutil.WriteFileAtomic` does all four and backs `LocalVFS.Write` and `StorageServiceVFS.Write`.
`vfs.moveFileIn` (resumable-upload commits, transcode output) flushes the staged file before renaming or linking
it, and the directory after. `storageutil.UploadFilesStreamed` (uploads to a named device) flushes its temp the
same way; where it cannot rename or link — another filesystem, or exFAT, which has no hard links — it copies
through `WriteFileAtomic` rather than into the real name.

Resumable uploads stage under `<data dir>/tmp/upload-sessions`. A session interrupted by a crash is never
committed, so no partial file reaches the user's folders; `storageutil.ClearTmpDir` removes the staged bytes on
the next start, and the client starts the upload again.

## Residual risk

In plain English, for support copy:

- **An upload that was still in progress when the power went out is lost** and has to be started again. It never
  shows up as a broken file.
- **An upload finished in the last moment before the cut** is either there, whole, or not there at all.
- **A vault change still being saved** is either saved or not; the vault always opens with the master password.
- **Moving the vault to a USB drive** can leave an old encrypted copy on the device it moved from if the power
  cut came at the very end; it is replaced the next time the vault moves back there.
- Hidden `.vfs-write-*` temp files interrupted by a power cut stay on disk (hidden from listings) until
  something removes them. They cost space, not correctness.
- Settings files (`settingsutil`) and trash metadata are written in place without a flush. A power cut during
  one of those writes can lose that setting or the trashed item's original location. They are outside this bar
  and tracked in #2611.
- A drive or SD card that lies about flushing, or fails outright, is a hardware failure no software ordering can
  recover from.

## How it is tested

Unit tests pin each ordering rule: `storageutil/durable_test.go`, `vaultutil/location_test.go`,
`backup/vault_migrate_test.go`.
