# Multi-instance audit

Everything one Quark process keeps in memory or on its own disk, and what goes wrong with each when a second
instance serves the same install. This is the audit #2972 asked for, in support of #2964 (several instances on
one database and one file store). It is the multi-instance counterpart of [capacity](capacity.md).

The question asked of every row: **if a different instance served the next request, what would go wrong?**

**Short version.** Quark assumes it is the only process in four places that destroy data, and those come before
anything else:

1. Startup resets the database when the recorded schema version is dirty or unknown to the binary (D1, D2). A
   second instance booting mid-migration, or an older binary during a rollout or rollback, drops every table.
2. Startup and shutdown empty `<data dir>/tmp` (F1), which holds every instance's in-flight uploads and
   transcodes.
3. File version history serializes its index rewrite with in-process mutexes (S5). Two instances saving one file
   delete each other's snapshot as a stray.
4. A vault password change re-keys every entry and re-unlocks only the instance that served it (S4). Any other
   instance keeps writing entries under the old key.

After those, the largest group is state that is simply invisible to the other instance: the event bus and every
cache hanging off it, upload sessions, download tokens, vault unlock state, the settings cache, and job cancel.
Sessions, job claiming, and most row-level work are already safe because they are single guarded SQL statements.

## Method

- Read from the code at `16f988b9` (`saddle/integration`; `main` was `7edb427d`). Every row cites the line it
  was read from. **Nothing here was checked by running two instances**: the harness that could do that is #2971,
  and the PostgreSQL backend (#2955) it needs has not landed.
- Read line by line: `deputil`, `internal/server` (boot, middleware, routes, content indexer), `internal/db`
  (hand-written files), `internal/install`, `cmd/quark`, `eventbus`, `jobutil`, `fileversionutil`,
  `ratelimitutil`, `settingsutil`, `usersettingsutil`, `requestlogutil`, `healthutil`, `iosemutil`, `uploadutil`
  (session store), `downloadutil`, `vaultcrypto`, `remoteutil`, `tlsutil`, `thumbnailutil`, the write and move
  paths of `pkg/vfs` and `storageutil`, most of `pkg/backup`, and the client's events, upload, download, vault
  and jobs services.
- Swept by grep for `sync.*`, `atomic.*`, goroutines, tickers, package vars, temp files and data-dir paths, with
  each hit read in context but not every line: `chatutil`, `authutil`, `albumutil`, `grouputil`, `calendarutil`,
  `photoutil`, `videoutil`, `bookutil`, `pptxutil`, `xlsxutil`, `sshutil`, `hostnameutil`, `aptutil`,
  `repairutil`, and the bodies of the storage detectors. A "no state" verdict for those rests on the sweep.
- Not verified: whether the web build emits a service worker (`internal/server/public/` is a stub in the
  worktree), and the hard-link and rename semantics of any particular network share.

Columns: **Bad** is the worst outcome (data loss, security, wrong data, failed request, wasted work, or safe).
**Issue** is the #2964 sub-issue that covers the row, or **uncovered**. "(unnamed)" means the row falls in that
issue's scope but its text does not mention it. Rows that are PostgreSQL porting work rather than
multi-instance work point at #2955.

## Database, migrations and startup

| ID | Where | What it holds or does | With two instances | Bad | Issue | Direction |
| --- | --- | --- | --- | --- | --- | --- |
| D1 | `internal/db/database.go:81-96`, `:183` | `initSchema` calls `staleMigrationState`; a `dirty` row in `schema_migrations` means `ResetDatabase` | golang-migrate marks the version dirty in its own transaction before each migration body. An instance booting while another migrates sees `dirty` and drops every table | data loss | #2970 (raised in its comments) | Never auto-reset on a shared database: a dirty or unknown version refuses to serve |
| D2 | `internal/db/database.go:187-191` | A recorded version missing from the binary's embedded migrations is "stale" and also resets | Release N starting against a schema migrated by N+1, during a rollout or a rollback, drops every table | data loss | #2970 (raised in its comments) | A version above the binary's highest means stay unready, within a stated skew |
| D3 | `internal/db/database.go:72-112` | `m.Up()` on every `ConnectToDatabase`. The sqlite driver's `Lock()` is an in-process flag | Two instances starting together both migrate; the loser fails on a non-idempotent statement and leaves `dirty` set, which feeds D1 | data loss | #2970 | Advisory lock around the migration step, or a one-shot `migrate` step before the rollout |
| D4 | `internal/db/reset.go:24-35`, `:70-123`; caller `pkg/util/authutil/authutil.go:1689` | Factory reset: per-object `DROP` with no enclosing transaction, then re-migrate, then `os.RemoveAll` of the files directory (`authutil.go:1665`) | Other instances get "no such table" mid-request, then keep their vault key, caches, index and `setupDone` (D9) for an install that no longer exists | data loss | uncovered | Refuse while more than one instance is live, or take an exclusive lock and tell every instance to restart |
| D5 | `internal/db/connect.go:15-23` | The main database is the SQLite file `<data dir>/quark.db` | Several hosts opening one SQLite file over a network mount depend on that share's locking | data loss | #2955, #2968 | Multi-instance mode requires PostgreSQL and refuses SQLite |
| D6 | `internal/db/connect.go:78-104` | `sharedQueries` pins one `*sql.Conn` for every sqlc query and strips cancellation | Not a correctness guard: `BeginTx` callers already use the pool. On PostgreSQL a dropped pinned connection is never replaced, so the instance fails every query until restart | failed request | #2955 | Pool with normal contexts on PostgreSQL; keep the pin for SQLite |
| D7 | `internal/db/dsn.go:47` | `busy_timeout(5000)`, no `journal_mode`, timestamps compared as text | Rollback journal: any writer blocks readers in other processes; 5 s then `SQLITE_BUSY` | failed request | #2955 | PostgreSQL DSN, real timestamp columns, `now()` |
| D8 | `internal/db/connect.go:106-122` | `<data dir>/quark.health.db`, opened lazily. Nothing writes to it outside tests; its one use is the factory reset | A SQLite file on the share that #2968 says must not exist | safe today | #2968 (raised in its comments) | Delete it, or keep it on instance-local disk |
| D9 | `internal/server/middleware/middleware.go:186` | `setupDone atomic.Bool`, cached forever once true | Converges on its own before setup. Stale only after D4 | wrong data | uncovered (with D4) | Follows D4 |
| D10 | `cmd/quark/serve/serve.go:44`; `pkg/util/storageutil/dir.go:98-110` | No PID file, lock file or instance id anywhere. The data dir is derived from the OS user with no override | Nothing distinguishes "my" work from another process's, and "shared files, private scratch" cannot be expressed: database, settings, certs, tmp, mounts and files all hang off one root | design blocker | uncovered | Give each instance an id, and split the root into a shared files root, a database DSN, and an instance-local state dir. Most rows below depend on this |
| D11 | `internal/server/server.go:57-60`, `:242-276` | `repairHomes`: find accounts and groups with no home folder, create folder and row | Two instances booting together race the find-then-create. The comment calls both idempotent; the bodies were not read | wasted work | #2966 (unnamed) | Run under the startup lock |

SQLite-only code that #2955 has to port, listed so nobody mistakes it for multi-instance work: `sqlite_master`
and `pragma_table_info` in `internal/db/database.go:163`, `:207` and `internal/db/reset.go`; FTS5 `MATCH` in
`pkg/util/searchutil/search.go:105`; `datetime('now')` and `IS` as null-safe equality in `sql/queries/jobs.sql`;
raw `?`-placeholder SQL in `pkg/vfs/sqlite_metadata_store.go` and `pkg/vfs/dbvfs.go`; `ATTACH DATABASE` in
`pkg/backup/chat_export.go:141`. One PostgreSQL trap is behavioral: the count-then-change guards that keep one
admin and one channel owner (`pkg/util/authutil/helpers.go:27-51`, `pkg/util/chatutil/helpers.go:297-332`) run
in a default-isolation transaction. SQLite's single writer makes them correct; under `READ COMMITTED` two
concurrent demotions can each see the other as the survivor.

Every `sql.Open` outside tests: `internal/db/connect.go:23` (main), `:46` (vault file), `:117` (health);
`pkg/backup/vault_export.go:53`, `pkg/backup/vault_import.go:25`, `pkg/backup/chat_export.go:72` (backup
transport files). All name the `sqlite` driver.

## Events and the caches behind them

| ID | Where | What it holds or does | With two instances | Bad | Issue | Direction |
| --- | --- | --- | --- | --- | --- | --- |
| E1 | `pkg/util/eventbus/eventbus.go:172-178`, `:210` | `Bus.subscribers`, fanned out to in-process channels | A change on A reaches no socket and no subscriber on B. Root cause of E3 through E10 | wrong data | #2965 | Relay between instances and republish locally |
| E2 | `pkg/util/eventbus/eventbus.go:177-183` | `seq atomic.Uint64`, with the promise that a database read after `Seq()` returns `n` reflects every event up to `n` | The promise covers local publishes only. `Seq` is never sent to the client (`json:"-"`, `:161`), so clients cannot be confused by two counters | wrong data | #2965 | Keep `Seq` per instance and restamp each relayed event through the local `Publish`. If a resume token is ever exposed, issue it from the database |
| E3 | `pkg/util/eventbus/eventbus.go:147`, `:154`; `pkg/util/accessutil/accessutil.go:548`, `:597` | `Audience` and job `UserID` are `json:"-"`; `FilterEvent` type-asserts `Data` to Go types | A JSON relay drops the audience and turns `Data` into a map, so chat and job events reach nobody, or everybody if the assertion is loosened | security | #2965 (unnamed) | A wire envelope that carries audience and owner and decodes to the concrete types |
| E4 | `internal/server/api/v0/events/stream_events.go:37`, `:73-82` | Each socket keeps an access snapshot, reloaded only on a locally heard `account_changed`, `access_changed` or `resync` | A share revoked or an account disabled through A leaves B's socket open and filtering with the old snapshot | security | #2965 | Relay these two kinds reliably; treat a relay gap as a resync |
| E5 | `pkg/util/accessutil/accessutil.go:1142-1149`; `pkg/util/deputil/deputil.go:150` | `accessutil.Cache`: per-account LRU versioned by `Bus.Seq`, nothing else invalidates it | Correct for local events, blind to remote ones. Same failure as E4 | security | #2965 | Keep per instance; correct once E2 holds |
| E6 | `pkg/util/indexutil/indexutil.go:40`; `internal/server/server.go:101-105` | `FileIndex`: the whole tree in memory, built by a full walk at boot, then kept current from local events. No TTL | Files changed through A are missing or ghosts in B's filename search until B restarts. Every instance walks the tree at boot | wrong data | #2965, #2956 | Feed from the relayed bus; rebuild on a relay gap |
| E7 | `pkg/util/fileutil/by_type_cache.go:35-40`, `:25` | `ByTypeCache`: up to 8 whole-tree listings, dropped on local file events, 5 minute maximum age | B's Docs and Sheets listings miss A's changes for up to 5 minutes | wrong data | #2965 | Invalidate from relayed events |
| E8 | `internal/server/content_indexer.go:33-56`, `:163-176` | Content indexer subscriber. `contentDevices.sync` deletes index rows for a serial missing from this instance's registry | Indexes only its own instance's writes. An instance that cannot see a drive deletes that drive's rows for everyone | wrong data | #2965 (deletion unnamed) | Relay events; run the subscriber and the device sweep on one instance |
| E9 | `pkg/backup/backup.go:147`; `pkg/backup/sync.go:17-32`; `internal/server/server.go:91-97` | `SyncWorker`: mirrors file events to the default backup drive, retry queue of 10,000 in memory | Only the instance that served the upload mirrors it, and only if it can see the drive; otherwise skipped with no retry. With a relay, every instance mirrors every event | data loss (in the mirror) | #2965 | One owner, fed by the relay |
| E10 | `pkg/util/chatutil/chatutil.go:1576-1601`; `internal/server/server.go:125` | `WatchKeyNeeds`: scans every channel again on membership events and publishes `chat_key_needed` locally | Key holders connected to B are never asked | wrong data | #2965 (unnamed) | Relay; run on one instance |
| E11 | `pkg/util/eventbus/types.go:36`, `:172` | Per-subscriber backlogs, collapsed to one `EventResync` on overflow | A backlog dies with the process, and there is no "you missed events from another instance" path | wrong data | #2965 | Emit a resync to every local subscriber when the relay reconnects |
| E12 | `pkg/util/eventbus/helpers.go:5-9` | Fixed subscriber ids (`file-index`, `content-indexer`, `sync-worker`, …); a second `Subscribe` under one id replaces the first | Safe today. Reusing them as shared consumer names would make instances evict each other | safe | #2965 (trap) | Keep ids local |

## Jobs and periodic work

`ClaimJob`, `FinishJob`, `UpdateJobProgress`, `RetryJob` and `CancelJob` are single statements guarded on
`status` (`sql/queries/jobs.sql:55-113`). No job runs twice from a claim race. The `jobs` table has no owner,
heartbeat or lease column, which is the cause of J1 through J3.

| ID | Where | What it holds or does | With two instances | Bad | Issue | Direction |
| --- | --- | --- | --- | --- | --- | --- |
| J1 | `sql/queries/jobs.sql:116-123`; `pkg/util/jobutil/jobutil.go:436` | `InterruptRunningJobs`: every `running` row fails at dispatcher start | Each instance start fails the other's live jobs. The owner keeps working, its `FinishJob` matches no row, and a Retry runs the job again | wrong data | #2966 | Owner and lease columns; interrupt only expired leases |
| J2 | `pkg/util/jobutil/helpers.go:141-157` | Lane occupancy counted from the in-memory `q.running` under `q.mu` | N instances run N times each lane's limit | wasted work | #2966 | Count in the claim query, or accept and document it |
| J3 | `pkg/util/jobutil/jobutil.go:325-345` | `Cancel` updates the row, then cancels the context only if the job is in this process's `q.running` | A cancel served by B flips the row; A's handler runs to completion and writes its output while the UI says canceled | wrong data | #2966 (unnamed) | The running instance cancels itself when its progress write matches no row (`helpers.go:221-223` already notices) |
| J4 | `pkg/util/jobutil/jobutil.go:155`, `:443-446` | Dispatcher sleeps on the in-process `wake` channel; it never polls | A job enqueued on a full or dying instance waits until some instance happens to enqueue or finish one | failed request | #2966 (unnamed) | Wake from the relayed `job_queued`, plus a slow poll |
| J5 | `pkg/util/jobutil/helpers.go:146-154` | A pending job whose kind is not registered gets a slot of one and fails with `ErrUnknownKind` | During a rollout the old instance claims and fails job kinds only the new build knows | failed request | #2970 (unnamed) | Do not claim kinds this instance does not know |
| J6 | `internal/server/server.go:82-85`, `:543` | Shutdown cancels running jobs and records them failed | Every rollout step fails the draining instance's jobs; nothing requeues them | wasted work | #2970 | Release to `pending` on a graceful drain |
| J7 | `internal/server/server.go:145-161` | Session purge, at boot and every 24 h | Idempotent delete, repeated | safe | #2966 | Keep; lock optional |
| J8 | `internal/server/server.go:167-198` | Trash purge, at boot and hourly, on the shared trash, then `accessutil.DeleteRows` | Every instance purges the same trash at once. The file-level purge skips missing entries (`pkg/vfs/helpers.go:885`) | wasted work | #2966 | Advisory lock |
| J9 | `internal/server/server.go:202-223` | Prune connected devices and finished jobs, hourly | Idempotent deletes over finished rows | safe | #2966 | Keep |
| J10 | `internal/server/server.go:132`; `internal/server/content_indexer.go:117-128` | `backfillContentIndex`: re-extracts every indexable file at every boot, 10 minute cap | N full passes over the shared mount per rollout; upserts are idempotent | wasted work | #2966 (unnamed) | Advisory lock, or a "backfilled at version" marker |
| J11 | `internal/server/server.go:136`; `internal/server/photo_hashes.go:17-33` | `backfillPhotoHashes` at every boot | N instances decode the same photos | wasted work | #2966 (unnamed) | Advisory lock |
| J12 | `pkg/backup/backup.go:80-86`; `pkg/util/deputil/deputil.go:125`; `pkg/backup/start_snapshot.go:101-111`, `:153` | `InMemoryBackupJobStore`, and the "already running" check that reads it. The snapshot runs in a detached goroutine | The client's 2 s status poll gets 404 on the other instance. A second start on B launches a concurrent snapshot onto the same target (F12, F13). A restart loses the job with no terminal state | data loss | uncovered | Move backup jobs onto the `jobs` table with a per-target lock |
| J13 | `pkg/util/fileutil/delete.go:127-167` | After a delete responds, a detached goroutine publishes the events and removes album, favorite, rotation and hash rows | An instance drained between the response and the cleanup leaves orphaned rows and never publishes | wrong data | #2970 (unnamed) | Shutdown waits for `deps.Background()`; today nothing waits on it |

## State that spans requests

| ID | Where | What it holds or does | With two instances | Bad | Issue | Direction |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | `pkg/util/uploadutil/uploadutil.go:253-263`; `pkg/util/uploadutil/session_store.go:29`, `:90` | `SessionStore.sessions`: id, owner, offset and an open file per resumable upload, staged at `<data dir>/tmp/upload-sessions/upload-*.part` | A chunk on another instance gets 404. The client restarts the file from zero, at most 3 times (`lib/services/upload_manager.dart`), so a multi-chunk upload almost never completes without affinity | failed request | #2967 | Session rows in the database, staged bytes on the share, a per-session lock for the append |
| S2 | `pkg/util/uploadutil/uploadutil.go:38`, `:42`; `session_store.go:331` | 32 sessions per account and 256 overall, counted over the local map | Both caps, and the staged-disk bound, multiply by N | security | #2967 (unnamed) | Count in the database |
| S3 | `pkg/util/downloadutil/downloadutil.go:45-50`; `internal/server/middleware/middleware.go:279-301` | `TokenStore.tokens`: 60 s unused, then a 10 minute idle window for range resumes | The browser's GET lands on B and gets a JSON 401 saved as the file; the app never sees an error because the download is a plain link | failed request | #2967 | A signed token (a keyed hash over user, path, serial, expiry) or a table |
| S4 | `pkg/util/vaultcrypto/vaultcrypto.go:45-51`; `pkg/util/deputil/deputil.go:202`; `pkg/util/vaultutil/config.go:239-241` | `VaultSession`: the derived key, one per process, auto-lock checked lazily against `unlockedAt` | Unlock on A, locked on B: the page flips every refresh. Lock on A leaves B unlocked. `ChangePassword` on A re-keys every entry and re-unlocks only A, so B writes new entries under the old key | data loss | #2967 (password change unnamed) | See the constraints in #2967's comments: never store or broadcast the key. Add a key generation to `vault_config` and reject a session holding a stale one |
| S5 | `pkg/util/fileversionutil/fileversionutil.go:94-101`; `pkg/util/fileversionutil/helpers.go:310-343` | 64 striped mutexes around read index, copy snapshot, `commit`. `commit` writes the index, then deletes every file in the store the index does not list | Two instances snapshot one file: both read the old index, and the second `commit` deletes the first's snapshot as a stray | data loss | #2967 | A cross-instance lock per store path, or the index in the database |
| S6 | `pkg/util/fileversionutil/fileversionutil.go:97-100` | `pending`: folders a file was trashed from since startup, swept on a local `trash_changed` | Delete on A, empty trash on B: no sweep, orphaned `.quark-versions` stores stay on disk. Already true across a restart | wasted work | #2965 (unnamed) | Relay, or a periodic sweep under a lock |
| S7 | `pkg/util/ratelimitutil/ratelimitutil.go:27-32`; `pkg/util/deputil/deputil.go:138`, `:144`, `:153` | Three `Limiter`s: per-IP token buckets for auth and vault, per-account for chat | Each limit is N times looser. The vault unlock limiter is the master password's only brute-force bound | security | #2967 | Shared counters for auth and vault |
| S8 | `pkg/util/ratelimitutil/ratelimitutil.go:139-146`; `pkg/util/deputil/deputil.go:147` | `LoginGuard`: failure counts, lockouts, and the addresses each account has signed in from. In memory on purpose (#1861) | Thresholds multiply by N, a lockout on A does not hold on B, and a rollout clears them all | security | #2967 | A table keyed on a hash; household boxes keep the in-memory guard |
| S9 | `pkg/util/settingsutil/settingsutil.go:85-104`, `:133-144`; `pkg/util/settingsutil/helpers.go:14-20` | `cached *Settings`, loaded once from `<data dir>/settings.json` for the life of the process. `Save` rewrites the whole file from the cache | B never sees A's change to a feature flag, the access-requests toggle, remote access or the theme. B's next save of any field reverts A's. An older build's save drops fields it does not know | data loss | uncovered | Settings rows in the database, one per key |
| S10 | `pkg/util/settingsutil/settingsutil.go:375-395` | `AuthSaltSecret`: 32 random bytes generated on first use, keying the deterministic salt for unknown usernames | Two instances on a fresh install each generate one and keep their own in the cache. `/auth/salt` then answers differently per instance for unknown users, which breaks the enumeration defense | security | uncovered | Create in the database with insert-or-ignore, then re-read |
| S11 | `pkg/util/requestlogutil/requestlogutil.go:30-32`, `:97-100` | `mu` around read, trim, write `…jsonl.tmp`, rename. "The one server process is the file's only writer" | Two admins deciding on different instances lose an entry, or collide on the fixed temp name and fail the request | data loss | uncovered | A table |
| S12 | `pkg/util/usersettingsutil/usersettingsutil.go:163` | Per-account JSON under `<data dir>/user-settings/`, no cache, written in place with `os.WriteFile` | Correct if the directory is shared, apart from a reader seeing a truncated file. Per-instance if it is not | failed request | uncovered | A table, or at least temp and rename |
| S13 | `pkg/util/deputil/dependencies.go:50-51`, `:242-249`; `internal/server/server.go:291-309` | `vaultDB`: a handle to `<device data dir>/vault.db`, swapped on a location change, falling back to the main database when unset | A location change on A swaps only A's handle. An instance that cannot see the device silently serves the main database's vault tables, a different vault | wrong data | #2969 (unnamed) | No external vault location in multi-instance mode; fail closed, no fallback |
| S14 | `pkg/util/iosemutil/iosemutil.go:74-93`; `pkg/util/downloadutil/downloadutil.go:145` | IO semaphores and zip slots sized from `runtime.NumCPU()`; the copy class is 2 because of the one disk | CPU classes are right per host. The copy class, bound by the shared disk, becomes 2N | safe | none needed | Keep per instance; note it in [capacity](capacity.md) |
| S15 | `pkg/util/healthutil/healthutil.go:39-52` | `Collector`: a 5 s sample of this host, and the "CPU high since" marker | `/health` reports whichever host answered; the hostname and numbers alternate per poll | wrong data | #2970 (unnamed) | Label with the instance id |

Confirmed safe: sessions. Tokens are random, only their SHA-256 is stored, and every request validates against
the `sessions` table (`pkg/util/authutil/authutil.go:1001-1012`, `internal/server/middleware/middleware.go:262-272`).
There is no in-memory session cache, signing key or CSRF secret. Connected-device tracking is a database upsert
(`middleware.go:143-163`). Albums, favorites, groups, calendar and chat rows are database-only.

## Local disk

Every path hangs off `storageutil.GetDataDir()` (D10). Each row says what a multi-instance install must do with
the path: put it on the share, or keep it on the instance.

| ID | Where | Path and writer | With two instances | Bad | Issue | Direction |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | `internal/server/server.go:479`, `:550`; `pkg/util/storageutil/tmp_dir.go:39` | `clearDataTmp` empties `<data dir>/tmp` at startup and shutdown: "scratch owned by a running process" | On a shared root, every instance start or stop deletes the others' staged uploads and transcodes | data loss | #2968 (unnamed) | `tmp/<instance id>/`; wipe only your own, reap the dead by lease |
| F2 | `pkg/util/transcodeutil/types.go:32`; `pkg/util/transcodeutil/helpers.go:262-274` | `prepareStaging` deletes staged files older than `processStart` | An instance that started after another's long transcode began deletes its live output | failed request | #2968 (unnamed) | Stage under the instance directory from F1 |
| F3 | `pkg/util/storageutil/durable.go:43-48`, `:83-110`; `pkg/vfs/helpers.go:143` | Every file write: temp beside the target, fsync, rename. Exclusive create links, or reserves the name with `O_EXCL` where links are unsupported | Readers never see a partial file. On a share without hard links the name exists as an empty file for an instant. A plain overwrite is last rename wins, as it is between two requests today. Temps orphaned by a crash are never reaped | safe | #2968 | Confirm rename and `O_EXCL` on the target share; reap stale `.vfs-write-*` |
| F4 | `pkg/vfs/helpers.go:203-212` | `moveAcrossDevices`: `os.Create` at the destination, then copy. Chosen by matching the error string | Another instance can read the half-written destination | wrong data | #2968 | Route through the atomic write; test the error with `errors.Is`, not its text |
| F5 | `pkg/vfs/helpers.go:424-484`, `:745-806` | Trash: directories and `.meta.json` sidecars, names carry 64 random bits | Naming is collision-safe. Restore is check-then-rename, a race the code already documents | safe | #2968 | Keep on the share |
| F6 | `pkg/util/thumbnailutil/cache.go:29-48`, `:94-114` | `<data dir>/cache/thumbnails`, deterministic key, unique temp, rename | Safe to share and safe to lose | safe | #2968 | Either; sharing saves regeneration |
| F7 | `pkg/util/thumbnailutil/client.go:44-111` | Client-rendered thumbnails stored in the same cache directory. The server cannot regenerate them | With a per-instance cache they exist only where the upload landed | wrong data | #2968 (unnamed) | The share. This makes the cache directory not purely a cache |
| F8 | `pkg/util/avatarutil/avatarutil.go:99-151` | `<data dir>/avatars/<user id>.jpg` or `.png` | Per-instance: a picture set on A is missing on B | wrong data | #2968 (unnamed) | The share, or the database |
| F9 | `pkg/backup/last_snapshot.go:18-37` | `<data dir>/last-snapshot-backup`, written atomically | Per-instance: the others report "never backed up" | wrong data | uncovered | The database |
| F10 | `pkg/util/storageutil/disk_probe.go:62-63`, `:145` | `.quark-probe-tmp`, a fixed name in the device data dir, truncated and removed per probe | Two probes destroy each other's file; the bogus speed class is cached for an hour | wrong data | #2968 (unnamed) | `os.CreateTemp` |
| F11 | `pkg/util/fileutil/xlsx.go:103` | `.<stem>.qsheet.converting`, a fixed temp name in the user's folder | Two conversions of one file collide. Possible in one process today | failed request | #2968 (unnamed) | A unique temp name |
| F12 | `pkg/backup/vault_export.go:46-53` | `vault_backup.db` built in place on the backup target after `os.Remove` | Two snapshots (J12) rewrite one SQLite file; a reader can open it half-built | data loss | uncovered (with J12) | Temp and rename, as `ExportChat` does |
| F13 | `pkg/backup/chat_export.go:43-62` | A fixed temp name, removed up front, then renamed | Two exports destroy each other's temp | failed request | uncovered (with J12) | A unique temp name |
| F14 | `pkg/util/tlsutil/tlsutil.go:27-46`; `pkg/util/tlsutil/helpers.go:26-44` | `<data dir>/certs/server.crt` and `.key`, regenerated at startup when the certificate does not name this host | On a shared root, hosts with different names overwrite each other's pair at every start, and an interleaving leaves a certificate whose key does not match. Per-instance, clients see a different certificate per request | failed request | uncovered | Terminate TLS at the load balancer in multi-instance mode |
| F15 | `pkg/util/vaultutil/location.go:23`, `:219`; `internal/db/vault_schema.go` | `<device data dir>/vault.db`, a SQLite file outside the migration set | A PostgreSQL main database does not remove it | data loss | #2968 (raised in its comments) | With S13: the vault stays in the main database |
| F16 | `pkg/util/storageutil/dir.go:112-113`; `pkg/util/storageutil/auto_mount.go:22-50` | `<data dir>/mounts/<serial>/` mount points | On a shared root, a mount point made on A's host is an empty directory on B's | wrong data | #2969 | Instance-local |
| F17 | `internal/install/install.go:77-118` | `useradd --system quark` with no fixed uid | Two hosts give `quark` different user ids, so files one writes to the share can be unreadable by the other. Containers built from one image do not have this | failed request | #2968 (unnamed) | Pin the uid and gid |

Host temp (`$TMPDIR`) is used for RAW conversion (`pkg/util/photoutil/raw_convert.go:98`, `:136`) and for
update downloads, with unique names and request scope. It stays per instance. There is no `flock`, POSIX record lock
or lock file anywhere in the backend; the only `O_EXCL` is the fallback in F3.

## One machine

| ID | Where | What it holds or does | With two instances | Bad | Issue | Direction |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | `pkg/util/remoteutil/remoteutil.go:25-42`; `internal/server/server.go:525-534` | Package globals `srv *tsnet.Server`, `running`, `lastErr`: one tailnet node and reverse proxy per process, started at boot | Status and pairing answer for whichever instance is hit. `Disable` stops one node and leaves the others up after "off" | security | #2969 | One owner, or off in this mode |
| M2 | `pkg/util/remoteutil/helpers.go:404-415`, `:238` | `stateDir()`: `/var/lib/quark/tsnet`, the machine and node keys | Shared: two processes run one node identity, and one can `RemoveAll` the directory under the other. Separate: N nodes | failed request | #2969 | Never on the share |
| M3 | `pkg/util/provisionutil/provisionutil.go:56`, `:64` | `DeviceID()` from hostname and machine id; `Enroll` reads and writes the household credential in settings | Different hosts are different devices; cloned containers are the same one. Two instances with no household both enroll and the last write wins (S9) | wrong data | #2969 (unnamed) | An install-level id in the database; enroll under a lock |
| M4 | `pkg/util/updateutil/helpers.go:217`; `internal/server/api/v0/version/do_update.go:39-43` | The in-app update replaces the binary and exits the instance that got the request | One instance updates and migrates the schema under the others, which then meet D2 | data loss | #2969 | Off in this mode; the image is the version |
| M5 | `pkg/util/updateutil/updateutil.go:457-472`; `cmd/quark/serve/serve.go:32` | `RunInstalledUpdate` execs a newer binary from `$QUARK_UPDATE_DIR`, which the container image puts in the data volume | On a shared volume every instance jumps version at its next restart, uncoordinated | data loss | #2969 (unnamed) | Ignore the update dir in this mode |
| M6 | `internal/server/server.go:140`, `:358-418` | `usbDeviceMonitor`: 5 s ticker, auto-mounts with `sudo mount`, `handled` map | Per-host. Two instances on one host race the mount | wasted work | #2969 | Off in this mode |
| M7 | `internal/server/server.go:139`, `:311-351` | `vaultDeviceMonitor`: 10 s ticker, `wasConnected := true` | An instance without the drive sees a disconnect on its first tick, locks its vault session and announces it | wrong data | #2969 | Off in this mode |
| M8 | `pkg/util/storageutil/service.go:115-132`, `:285-301`; `pkg/vfs/registry.go:5`; `pkg/util/deputil/deputil.go:180-195` | `StorageService` device caches (10 s), the devices-changed listeners, and the VFS registry built from them | `files` is the same everywhere. `files:<serial>` exists only where the drive is, and a mount or unmount re-syncs only the instance that served it | failed request | #2969 (unnamed) | Devices in this mode are configured shared mounts, not detected hardware |
| M9 | `pkg/util/deputil/deputil.go:156-162`; `pkg/util/sshutil/sshutil.go:28`; `pkg/util/hostnameutil/hostnameutil.go:80` | `sshSystem`, `hostnameSystem`, `repairSystem`: act on the host that served the request | An SSH key revoked on A is still valid on B. A rename changes one host and regenerates its certificate (F14) | security | #2969 (unnamed) | Off in this mode, with the pages saying why |
| M10 | `internal/install/dns_sd.go:9-38` | Avahi service file advertising `_quark._tcp` on port 443 | Every host advertises, so the app lists one install N times and pins itself to an instance behind the load balancer's back | wrong data | #2969 (unnamed) | Do not advertise in this mode |
| M11 | `internal/install/system_service.go:60-78`; `pkg/util/memutil/memutil.go:76-88` | One fixed unit name, ports 80 and 443, `GOMEMLIMIT` at 60% of host RAM | Two instances on one host overwrite the unit, fail to bind, and together claim 120% of RAM | failed request | none needed | One instance per host or container; say so in `docs/container.md` |

## Shutdown and rolling upgrades

| ID | Where | What it holds or does | With two instances | Bad | Issue | Direction |
| --- | --- | --- | --- | --- | --- | --- |
| U1 | `internal/server/server.go:537-552` | On SIGTERM: stop the sync worker, jobs and tailnet, close upload sessions, wipe tmp, `os.Exit(0)`. There is no `http.Server.Shutdown` in the tree | In-flight requests, downloads and sockets are cut with no drain and no close frame; `deps.Background()` is never waited on | failed request | #2970 | Flip readiness, drain with a deadline, close sockets with a reconnect code |
| U2 | `internal/server/routes.go:115-123` | `NoRoute` answers every unmatched path, `/api/` included, with `200 text/html` | A new frontend calling a new endpoint on an old backend gets HTML: reads fail to parse, and a write "succeeds" having done nothing. The client already works around this once (`lib/services/auth_service.dart:738-756`) | wrong data | #2970 (unnamed) | JSON 404 under `/api/` |
| U3 | `internal/server/routes.go:44-45`, `:107`; `web/index.html:297` | The web build is embedded per binary, entry file names carry no content hash, and no `Cache-Control` or `ETag` is set | `index.html` from build N and `main.dart.js` from N+1: a blank page during the rollout window | failed request | #2970 | Version-prefixed asset paths, or one shared copy; `no-cache` on the entry files |
| U4 | `lib/services/files_service.dart:1166`; `lib/pages/settings_page.dart:467` | The client never compares its build with the server's; `/version` only feeds a label | Nothing tells a tab loaded from build N to reload once the fleet is on N+1 | wrong data | #2970 | Stamp responses with the build; prompt a reload on mismatch |
| U5 | `lib/services/auth_service.dart:739-766`; `lib/services/auth_secret.dart:34-36` | The client probes `GET /auth/salt` to learn which credential shape the Quark takes, then posts | Probe on N+1, post on N: a sign-in rejected on one attempt and accepted on the next | failed request | #2970 (unnamed) | The N and N+1 compatibility rule has to cover auth |

## The client

| ID | Where | What it assumes | With two instances | Bad | Issue | Direction |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | `lib/services/events_service.dart:121`, `:225-226`; `lib/utils/events_config.dart` | Events missed while disconnected are gone, so a reconnect means reload. Backoff 1 s to 30 s with jitter | Files, Photos, Trash, chat messages and account state reload on reconnect and are fine on a different instance | safe | none needed | Keep |
| C2 | `lib/controllers/jobs_controller.dart:123`; `lib/controllers/notifications_controller.dart:242`; `lib/controllers/chat_controller.dart:179`; `lib/controllers/hostname_controller.dart:37`; `lib/services/content_search_service.dart:69` | These listen to `events` only, never to `reconnects` | They stay stale after a reconnect, which a rollout forces on every client | wrong data | uncovered | Deliver a synthetic `resync` on reconnect; most of them already handle that kind |
| C3 | `lib/utils/auto_refresh_mixin.dart:116` | Pages with the mixin refetch every 15 s by default; the user can turn it off | Bounds E1's staleness on those pages. It does not cover the jobs badge, notifications, feature flags or a hostname change | wrong data | #2965 | Not a fix; fix E1 |
| C4 | `lib/widgets/system/storage_tab.dart:254-286` | The 2 s backup status poll reaches the process that started the backup, and swallows errors | The bar stalls on the other instance; if the starter is replaced the poll never ends | failed request | uncovered (with J12) | Follows J12 |
| C5 | `lib/services/authenticated_service.dart:131-133` | Any 401 means the token is dead everywhere, so the client signs out | Safe while every instance reads the same `sessions` table and outages answer 503 | safe | #2955 (trap) | Read-your-writes for sessions; no 401 for a local reason |
| C6 | `lib/pages/vault_page.dart:79`; `lib/services/vault_service.dart:228-239` | "Unlocked" holds until auto-lock | Follows S4: the unlock form reappears every refresh | failed request | #2967 | Follows S4 |

## Uncovered: proposed new sub-issues

These rows have no home in #2965 through #2971. Grouped into the issues they would make:

1. **An instance id, and a root split into shared and instance-local** (D10). A prerequisite for F1, F2, J1 and
   M2, and for deciding every "if the data dir is shared" row.
2. **Settings and small files move to the database** (S9, S10, S11, S12, F9): `settings.json` and its cache, the
   auth salt secret, the account-request history, per-user settings, the last-snapshot marker.
3. **Backup jobs on the job queue** (J12, F12, F13, C4): the in-memory backup job store, the per-target lock,
   and the two export files that are not built safely.
4. **Factory reset with more than one instance** (D4, D9).
5. **TLS in multi-instance mode** (F14): belongs in #2969's switch, which does not mention it.
6. **Client resync on reconnect** (C2).

Rows marked "(unnamed)" should be added to the text of the issue named beside them. The ones that change an
issue's shape:

- **#2965**: the relay needs a wire envelope for `Audience` and job `UserID` (E3), and `Seq` must be restamped
  locally, never carried across (E2). Access and account changes are a security path, so "best effort" delivery
  is not enough for them (E4).
- **#2966**: cancel (J3), the wake channel (J4), and the boot-time backfills (J10, J11, D11) are missing.
  Shutdown should release jobs to `pending` (J6).
- **#2967**: the vault password change loses data, on top of the unlock-state problems (S4). The upload caps
  multiply (S2).
- **#2968**: the tmp wipe (F1) and the transcode staging reaper (F2) delete other instances' live files, which
  is worse than "orphaned staging". Client thumbnails and avatars are durable data in directories that look like
  caches (F7, F8).
- **#2969**: add `RunInstalledUpdate` (M5), the storage service and VFS registry (M8), SSH, hostname and repair
  (M9), DNS-SD (M10), the external vault location (S13, F15), and TLS (F14).
- **#2970**: `NoRoute` returning HTML for API paths (U2), unknown job kinds (J5), the post-response cleanup
  goroutine (J13), and auth capability probing (U5).

## Guarding against new per-process state

A lint can catch the declaration and cannot judge it. `scripts/check-go-structure.bash` could fail a new
package-level `var` of type `sync.Mutex`, `sync.RWMutex`, `sync.Map`, `map[…]` or `atomic.*` outside an
allowlist, the way it already confines `os` calls. That would have flagged `settingsutil`, `requestlogutil`,
`remoteutil` and `transcodeutil.processStart`. It would not have flagged anything on `deputil.Dependencies`,
which is where most of this page lives and where AGENTS.md tells new state to go, and it cannot tell a CPU
semaphore (fine) from an upload session map (not).

So the practical guards are two. The harness in #2971 is the only check that proves behavior. This page is the
check at review time: a change that adds a member to `Dependencies`, a goroutine to `server.go`, or a path under
the data dir adds a row here saying which of the dispositions it takes. The lint is cheap enough to add alongside
#2971 as a prompt to do that, and should not be mistaken for coverage.
