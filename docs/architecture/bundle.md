# Moving a whole Quark to a new install

A bundle is one tar file holding an install's database rows and its files: what a new install needs to be that
Quark (#3838). `quark bundle export` takes it on the source, and `quark bundle import` starts a new, uninitialized
install from it. Either side may run on SQLite or on PostgreSQL, so all four directions work:

| Source     | Target     |
| ---------- | ---------- |
| SQLite     | SQLite     |
| SQLite     | PostgreSQL |
| PostgreSQL | PostgreSQL |
| PostgreSQL | SQLite     |

The code is `bundleutil.Export` and `bundleutil.Import` in
[`pkg/util/bundleutil`](../../pkg/util/bundleutil/bundleutil.go), over `db.ExportDatabase` and
`db.ImportDatabase` in [`internal/db/bundle.go`](../../internal/db/bundle.go). The command is a thin wrapper
around them, and the admin page will call the same functions once an admin can choose the backend there (#2961).

## What a bundle holds

| Entry       | What it is                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------- |
| `quark.db`  | every row of the database, as a SQLite file at the source build's schema. Always the first entry |
| `files/`    | the internal drive's files, the version store included                                        |
| `trash/`    | the internal drive's trash                                                                    |
| `avatars/`  | profile pictures                                                                              |

The database is a SQLite file whichever engine the source runs on: one file, no server needed to read it, and
`db.MoveToPostgres` already fills PostgreSQL from one. Accounts, sessions, groups, albums, access grants, the
vault, the chat and the install id are all rows in it.

Nothing else in the data directory is carried: `cache/` and `tmp/` are rebuilt or staging, `certs/` and
`mounts/` belong to the machine, and the files an older Quark kept its settings in are rows in the database
now. A USB drive's files are on the drive, which moves with it.

## Taking a bundle

```bash
sudo systemctl stop quark
sudo -u quark quark bundle export -o /tmp/quark-bundle.tar                          # on SQLite
sudo -u quark quark bundle export -o /tmp/quark-bundle.tar --database-url "$URL"    # on PostgreSQL
```

- **It only reads the source.** A SQLite `quark.db` is opened with `mode=ro`, and PostgreSQL is read in one
  `REPEATABLE READ READ ONLY` transaction. The rows are one snapshot; the files are read after it.
- **Stop the service first** so the rows and the files agree. A running server cannot corrupt the bundle, but
  what it writes after the snapshot would be missing from it, and a file uploaded meanwhile may have no row.
- **Run it as the service user,** so `--data-dir` defaults to the install's data directory.
- **`--database-url`** names the PostgreSQL database the install runs on. Leave it out on SQLite. Without it the
  command reads `QUARK_DB_BACKEND` and `QUARK_DATABASE_URL` as the server does.
- **The source must be at this build's schema.** If it is older, start this build on it once so it migrates,
  stop it again, and rerun. The export will not migrate it, because that would change it.
- **`-o`** must name a file that does not exist yet. A failed export removes what it wrote.

## Starting a new install from it

```bash
sudo systemctl stop quark
sudo -u quark quark bundle import /tmp/quark-bundle.tar                          # onto SQLite
sudo -u quark quark bundle import /tmp/quark-bundle.tar --database-url "$URL"    # onto PostgreSQL
```

The target is a new install: its database is empty, or migrated with no account yet. One that has an account is
refused before anything is written, files included, and nothing on it changes. There is no merge.

1. The bundle's `quark.db` is copied to a temp file and migrated to this build's schema, so a bundle from an
   older build imports into a newer one.
2. The files are written into the data directory, each through an `os.Root` on it, so no name or link in the
   bundle reaches outside it. An entry outside `files/`, `trash/` and `avatars/` stops the import.
3. The rows go in last, in one transaction. On PostgreSQL that is `db.MoveToPostgres`
   ([Moving to PostgreSQL](postgres-move.md)): the target is migrated, its seeded rows are truncated, every table
   is copied with `COPY`, and the identity sequences are moved past the copied ids. On SQLite the target
   `quark.db` is created and migrated if need be, every table is emptied and then filled row by row with foreign
   keys checked at the commit.

Ids come back as they were, so a vault item and a chat message still belong to the same account. Every copied
table's row count is checked against the bundle's before the commit, and a mismatch rolls the copy back.

When it finishes it prints each table's row count and the files placed. On PostgreSQL, point the service at the
database with `sudo systemctl edit quark` (`QUARK_DB_BACKEND=postgres` and `QUARK_DATABASE_URL`), then start it
and sign in with an account from the bundle.

## Safety

- **A failed or interrupted import leaves the target uninitialized.** The files are placed before the rows, and
  the rows are one transaction, so until the commit the install has no account. Running the import again writes
  the same files over the ones already placed and starts the copy over.
- **A finished import is not repeated.** The install has accounts after it, so a second run is refused.

## Derived data

Rebuilt rather than copied, as for [the in-place move](postgres-move.md#derived-data):

- **Content search** (`file_content`) is left empty in the bundle and on the target. The server's startup
  backfill extracts it again from the files.
- **Filename search** is in memory and built from the files when the server starts.
- **SQLite's FTS5 indexes** (`file_content_fts`, `music_tracks_fts`) are filled by their triggers as the rows
  arrive on a SQLite target, and are not in the PostgreSQL schema at all.
