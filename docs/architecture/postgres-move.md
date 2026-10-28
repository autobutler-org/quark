# Moving an install from SQLite to PostgreSQL

An install that has been running on SQLite moves to PostgreSQL with one command, `quark move-to-postgres`
(#2962). It copies every row of `quark.db` into an empty PostgreSQL database and checks that each table ends
with as many rows as it started with. The code is `db.MoveToPostgres` in
[`internal/db/move_postgres.go`](../../internal/db/move_postgres.go); the command is a thin wrapper around it.

**There is no way back.** Moving from PostgreSQL to SQLite is not supported. What keeps the move reversible
is that the SQLite file is never touched: until the service is pointed at PostgreSQL, and for as long as you
choose to point it back, it starts on SQLite with the data it had when the move ran.

## Running it

```bash
sudo systemctl stop quark
sudo -u quark quark move-to-postgres --database-url 'postgres://quark:secret@db.example:5432/quark'
```

- **Stop the service first.** The copy reads one consistent snapshot of the SQLite file, so a running server
  cannot corrupt it, but anything the server writes after the snapshot would not reach PostgreSQL.
- **Run it as the service user.** `--sqlite` defaults to `quark.db` in the data directory of whoever runs the
  command, which for the service account is the install's. Pass `--sqlite` to name a file elsewhere.
- **`--database-url`** defaults to `QUARK_DATABASE_URL`. The database must be empty, or one Quark has migrated
  but no account has been created in yet.
- **The SQLite database must be at this build's schema.** If it is older, start this build on SQLite once so it
  migrates, stop it again and rerun. The command will not migrate the file itself, because that would change it.

When it finishes it prints each table's row count, the total and the time taken, then the next step: add
`QUARK_DB_BACKEND=postgres` and `QUARK_DATABASE_URL` to the service with `sudo systemctl edit quark`, a drop-in
that survives the unit being rewritten by `quark install`, and start the service. To abandon the move, start
it without them.

## What it guarantees

- **The SQLite file is never modified or deleted.** It is opened with `mode=ro`, so the driver refuses every
  write, and a missing file is an error rather than a new empty database.
- **A failed or interrupted run leaves nothing behind.** The whole copy into PostgreSQL is one transaction:
  emptying the tables, the copy, the identity sequences and the count check. Any error, a count that does not
  match included, rolls it back.
- **Rerunning is safe.** After a failed run PostgreSQL is as it was, so the next run starts over. After a
  successful run the database has accounts in it, and the move refuses to run again rather than overwrite what
  the server has written since.
- **The target is migrated first,** through the same code the server's startup uses, so it refuses a database
  Quark did not make, one marked dirty, or one at a newer version, with the same messages.

## How the rows move

Every base table in the PostgreSQL schema except `schema_migrations` is emptied with
`TRUNCATE ... RESTART IDENTITY`, which clears the rows the migrations seed (the install id, the `everyone`
group, the default calendar and chat channel) so that SQLite's own take their place. The install keeps its
install id.

Tables are copied in foreign-key order, read from `pg_constraint`, each one after every table it references. A
table that references itself, like `photo_albums.parent_id`, arrives in one `COPY` statement, and PostgreSQL
checks a non-deferrable foreign key at the end of the statement, so the order of its rows does not matter.

Each table is streamed with `COPY FROM STDIN`: one row is in memory at a time, and every value is converted to
its PostgreSQL column's type.

| PostgreSQL column  | What SQLite hands back                                 | Conversion                               |
| ------------------ | ------------------------------------------------------ | ---------------------------------------- |
| `TIMESTAMPTZ`      | a `time.Time`, or text from before `_time_format`      | to UTC; text in SQLite's datetime form or RFC 3339 is parsed, anything else stops the move naming the value |
| `BOOLEAN`          | the integer 0 or 1                                     | `false` / `true`                         |
| `BIGINT`           | an integer, including a 0/1 flag and an autoincrement id | as it is, ids included                  |
| `DOUBLE PRECISION` | a float, or an integer SQLite stored in a `REAL`       | to a float                               |
| `BYTEA`            | a blob, or text stored in a `BLOB` column              | the bytes                                |
| `TEXT`             | text, or a number stored in a `TEXT` column            | as text                                  |

A `NULL` stays `NULL`, and a value of any other type stops the move with the table and column named. Ids are
copied as they are, and each identity sequence is then moved past the highest id copied, so the next insert
gets a new one.

After each table the counts are compared, `SELECT COUNT(*)` on both sides, the SQLite one inside the same
snapshot the rows came from.

## Derived data

- **Content search** (`file_content`) is left empty, not copied. It is the text extracted from every
  document, and the server's startup backfill extracts it again from the files on every device, so the first
  start on PostgreSQL rebuilds it. SQLite's FTS5 index over it, `file_content_fts`, is not in the PostgreSQL
  schema at all; content search on PostgreSQL is #2958.
- **Music search**'s FTS5 index, `music_tracks_fts`, is not in the PostgreSQL schema either. The library itself,
  `music_tracks`, is copied.
- **Every PostgreSQL index** is built by PostgreSQL as the rows arrive; none is copied.

## Downtime

The service is stopped for the whole copy, so the downtime is the command's run time plus a restart. No
timing has been measured yet. It grows with the number of rows rather than with the size of the files, which
stay on disk: the tables are accounts, sessions, albums, photo hashes, vault and chat rows, jobs and VFS
metadata. `file_content`, the extracted text of every document and the largest table on an install with many
documents, is not copied, so it costs the move nothing; its rebuild runs in the background after the server
is back. The command prints the time it took, which is the number to quote for an install of that size.

## Not covered

- **The admin page.** The backend is chosen by environment variables when the server starts, so a move started
  from the admin page needs a persisted backend choice first. That is #2961; `db.MoveToPostgres` is what it
  will call.
- **PostgreSQL to SQLite.** Not supported, as above.
