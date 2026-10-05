# Capacity

How many people one Quark serves at once, what runs out first, and what moves each limit. This is the audit
#2507 asked for: the concurrency model as the code stands, numbers measured with the harness that ships in
`internal/server/stress`, the defects found along the way, and a ranked list of what to fix. The research
comments on #2507 carry the per-operation costs this page does not repeat (HEIC decodes, zip throughput, TLS
handshakes) and their scaling to the target boards.

**Short version.** As shipped, one connection to SQLite carries every query in the process, and every request
also writes to it. Once the health endpoint stops queuing (#2750, fixed here), that connection is the first
wall: throughput stops growing at a few hundred requests a second, and at around 500 open apps the queue grows
faster than it drains until the server stops answering. Giving reads a pool and dropping the per-request write
moved the same host from 426 to 1,728 req/s at 500 clients and from a wedge to 1,335 req/s at 2,000. Past that,
the client's refresh-on-every-event turns each shared upload into a request storm.

## The concurrency model

| Piece | How it is shared | Bound |
| --- | --- | --- |
| HTTP server (`internal/server/server.go`) | gin on `serverutil.NewHTTPServer`, one goroutine per connection, HTTP/2 offered over TLS | 10 s for the handshake and headers, 2 min idle, 64 KiB of headers; no whole-request deadline, so uploads, downloads and the WebSocket are unbounded (#2755) |
| sqlc queries (`internal/db/connect.go`) | **one pinned `*sql.Conn`** for the whole process; the driver connection's mutex serializes every statement. Callers' cancellation is stripped (#2743), so an abandoned query still runs | none: queue grows without limit (#2766) |
| Transactions, FTS, VFS metadata | the `*sql.DB` pool, unbounded `MaxOpenConns`, contending with the pinned connection through the file lock | `busy_timeout(5000)` |
| SQLite settings (`internal/db/dsn.go`) | rollback journal (`DELETE`), `synchronous=FULL`, foreign keys on, 5 s busy timeout. FTS5 runs on the pool. See [durability](durability.md) before changing the journal | — |
| Per-request writes | `trackDevice` upserts `connected_devices` in a new goroutine after **every** request; `RenewSession` at most hourly per session | none (#2766, #2756) |
| Event bus (`pkg/util/eventbus`) | `Publish` loops every subscriber under an `RLock`; each subscriber has a 16-slot channel and a full one **drops** the event silently | 16 per subscriber (#2753) |
| Events WebSocket (`/api/v0/events`) | two goroutines per socket; filters, re-encodes and writes each event on its own goroutine; `account_changed` and `access_changed` make **every** socket query the database | none (#2764) |
| Internal subscribers | file index, content indexer and backup sync, each one goroutine doing its work inline | share the drop policy (#2753) |
| IO semaphores (`pkg/util/iosemutil`) | one per class of work, 30 s wait then 503: **decode** (thumbnails, JPEG conversion, hash backfill), **video** (ffmpeg frame grabs), **raw** (RAW conversion), **copy** (backup sync and snapshot); held through the response write. One class running flat out never takes another's slots (#2762) | from `runtime.NumCPU()` (n): decode max(2, n/2), video max(1, n/2), raw max(1, n/4), copy 2 — 2/2/1/2 on a 4-core board |
| Job queue (`pkg/util/jobutil`) | SQLite-backed, 1 encode lane and 2 copy lanes, FIFO across users; `q.mu` held across the claim queries | lanes; queue depth unbounded |
| Rate limiters (`pkg/util/ratelimitutil`) | map of IP → limiter behind one mutex, auth and vault paths only, swept every 5 min | ~200 B per IP |
| Upload sessions (`pkg/util/uploadutil`) | map behind one mutex, O(1) lookups; per-session mutex held for one chunk's `io.CopyN` | one fd each, 24 h TTL, no count cap (#2756) |
| Health collector (`pkg/util/healthutil`) | one `Collector` for every `/health` call | one host read per 5 s, shared (#2750) |
| Filename index (`storageutil.FileIndex`) | one folder tree per device; linear scan per search under `RLock`, stopping at 500 readable matches | ~300–480 B per file (#2760) |

Streaming is in good shape: uploads, downloads and archive entries go through `io.Copy`/`http.ServeContent`, and
no handler on a file path buffers a whole body (the one unbounded read is inside `gen2brain/heic`, which #2378
removes). The events socket returns when its client goes away (`conn.CloseRead`), so a closed app does not leave
its goroutines behind.

## Measured

### Method

`make test/stress/capacity` builds the backend, starts it on a throwaway `HOME` with the perf fixtures, and runs
`TestCapacity` (`internal/server/stress`, behind the `stress` build tag). Each simulated client is one app on the
Files page, with its own connections and User-Agent:

- one events WebSocket, reconnecting after 2 s when dropped;
- the page's refresh — `/health` and `/access/mine` on their own, `/storage/devices/status` at most every 10 s,
  then the listing and `/files/recent` — at start, every 15 s, and on every listing event the socket delivers,
  never two within a second (`AutoRefreshMixin`);
- 1 in 100 clients uploads a 4 KiB file into `groups/everyone` every ~4 s, which every account can read.

Clients arrive over the first 10 s of each 30 s level and share 20 member sessions. The report gives latency per
route, failures, requests still unanswered when the level ended, event delivery (upload events received against
uploads × clients), and the server's peak RSS and thread count from `/proc`. `STRESS_USERS`, `STRESS_DURATION`
and the other knobs are read from the environment (`helpers_test.go`).

Host: Intel Core Ultra 7 355 (8 threads), 30 GB, Linux, Go 1.27.1, plain HTTP (`QUARK_INSECURE=true`, so no TLS
cost). The harness runs on the same host and competes with the server for CPU, and other work shared the machine,
so each number is one run: a difference under about 1.5× between two of them is noise (see [on disk](#on-disk)). `mktemp` puts the data directory under `$TMPDIR`; on this host that is tmpfs, so
**fsync costs nothing** in the main runs. The [on-disk runs](#on-disk) repeat them on NVMe. Neither is the target
hardware: see [what this means on a board](#what-this-means-on-a-board).

Variants were throwaway builds of this branch, never committed: `trackDevice` writing at most once a minute per
(IP, User-Agent); that plus `journal_mode=WAL`, with `synchronous=NORMAL` and with the default `FULL`; and that
(WAL, `FULL`) plus `Queries` over the `*sql.DB` pool with `SetMaxOpenConns(16)`.

### Results (tmpfs)

Requests per second over the whole level, listing p50 (the `/files` home listing), and requests still unanswered
when the level ended.

| Build | 100 clients | 500 clients | 2,000 clients |
| --- | --- | --- | --- |
| As shipped, before #2750 | 109 req/s, list 321 ms, `/health` p50 **5.4 s**, 290 threads | 119 req/s, list 6–8 s, `/health` 13 s, 769 threads | wedged: 6 requests answered in 30 s, no socket opened |
| As shipped + #2750 | 118 req/s (all that was asked), list 126 ms | 426 req/s, list 3.3 s, 1,468 unanswered | **wedged**: 112 req/s, 2,575 sockets failed to open, 5,749 unanswered |
| + `trackDevice` once a minute | 128 req/s | 797 req/s, list ~1.9 s | wedged the same way |
| + WAL (`synchronous=NORMAL`) | 114 req/s | 788 req/s | wedged the same way |
| + WAL (`synchronous=FULL`) | — | 822 req/s | — |
| + read pool of 16 | 140 req/s | **1,728 req/s, list 47 ms**, 85 unanswered | **1,335 req/s**, all 2,000 sockets open, list 2.3 s |

Server memory stayed small throughout: 135 MiB peak at 100 clients, ~290 MiB at 500, 530–800 MiB at 2,000 (a few
hundred KiB per connected app, mostly goroutines, sockets and queued requests). No run returned a 401, 429 or 5xx.

Upload-event delivery fell with load on every build: 85–89% at 100 clients, 66–88% at 500, 26% at 2,000 as
shipped and 81% with the pool. The missing share is the bus dropping events for sockets whose 16 slots were full.

### What the first wall is

A goroutine dump of the as-shipped server 25 s into the 2,000-client level held 22,085 goroutines, **13,637 of them
in `sync.Mutex.Lock` on the one `database/sql.driverConn`**: 3,412 `GetSession`, 2,549 `IsUserAdmin`, 1,589
`ListPathAccessForUser`, 382 `UpsertConnectedDevice`. Every authenticated request makes two or three reads on that
connection before its handler runs, plus a write afterwards. Throughput is whatever that one connection can do,
whatever the core count, and because cancellation is stripped, the queue keeps the work of clients that already
gave up: a backlog from one level was still draining when the next began.

Before #2750, `/health` was in front of it. Every call slept 100 ms in `cpu.Percent` and read every hwmon sensor
through sysfs, which the kernel serializes: one call took 171 ms, 20 concurrent 752 ms, 100 concurrent 4.0 s, and
the first read after idle 8.4 s on this laptop. Each blocked read pinned an OS thread (290 at 100 clients).

### On disk

The same builds with the data directory on the host's NVMe drive (`TMPDIR` under `build/`), so commits are really
flushed. Requests per second, then listing p50.

| Build | 100 clients | 500 clients | 2,000 clients |
| --- | --- | --- | --- |
| As shipped + #2750 | 132 req/s, 121 ms | 502 req/s, 2.9 s, 1,370 unanswered | — |
| + `trackDevice` once a minute | 127 req/s, 299 ms | 183 req/s, 7.3 s on the first run; **789 req/s, 1.9 s** on a rerun | — |
| + WAL (`synchronous=FULL`) | 121 req/s, 273 ms | 549 req/s, 2.5 s | — |
| + read pool of 16 | 119 req/s, 32 ms | **1,527 req/s, 311 ms** | **1,438 req/s**, 2.3 s, all 2,000 sockets open |

The two runs of the same debounce build differ by 4×, which is the size of this host's run-to-run noise when
other work shares it: differences under about 1.5× between single runs here mean nothing. What holds on every run,
tmpfs or disk, is the read pool's 3–4× and the end of the wedge at 2,000. An NVMe flush takes well under a
millisecond; on SD or eMMC it is 2–20 ms, which is where the write half of #2766 and WAL earn their keep (the
research comment on #2507 measured 78 requests/s with real flushes as shipped against 8,168 with WAL and `synchronous=NORMAL`).

## What this means on a board

The target boards (#2507) are 4× Cortex-A55 to A76 with 2–8 GB and SQLite on SD or eMMC. The research comments
scale per-thread work by 4–5× (A55 against a desktop core) and put a flushed rollback-journal commit at 3–15 ms
on SD, so 25–100 commits/s. Applied to the measurements above:

| Active apps | As shipped | After #2766 (pool, WAL, no per-request write) |
| --- | --- | --- |
| 10 | fine | fine |
| 100 | at or past the commit ceiling on SD; health and listings slow down; one shared upload refreshes every app | fine for the request path; uploads into shared folders still fan out (#2763) |
| 500 | over: the shared connection queues and the server stops answering | request path near one core; event-driven refreshes dominate |
| 2,000–3,000 | not viable | not viable on an A55 board without #2763 and #2764; plausible on an 8-core A76 board with them, memory permitting (#2760, #2761) |

Memory is not the first limit. The idle server is 50–100 MB, an app costs a few hundred KiB while connected, and
the filename index costs ~0.3–0.5 KB per file on the appliance (#2760). Decodes are refused above 64 MP
(`photoutil.MaxDecodePixels`) from the header alone, so one costs at most 256 MiB at four bytes a pixel (512 MiB for a 16-bit
PNG), and the decode class admits two at once on a 4-core board. `quark serve` sets a Go soft memory limit of 60% of RAM unless `GOMEMLIMIT` is
set, so the heap collects near its live set, and `quark install` writes a systemd drop-in
(`/etc/systemd/system/quark.service.d/50-memory.conf`) with `MemoryHigh` at 80% and `MemoryMax` at 90% of RAM, which
cover ffmpeg children too: the kernel throttles and then kills inside the service before the board swaps (#2761).

## Known limits

- **One connection for every query, and a write per request** (#2766). The first wall, above.
- **Every app refreshes on every readable change anywhere** (#2763). In the 100-client run, 7 uploads caused 620
  of the 820 refreshes, about 70% of all requests. Reconnects have no jitter, so a restart is a synchronized
  stampede.
- **Event fan-out is per socket**: `account_changed` and `access_changed` make every socket query the database,
  and each event is encoded once per subscriber (#2764).
- **The event bus drops events**, including for the backup sync and the indexers, which then silently miss files
  (#2753).
- **Whole-tree walks per request**: Photos, Recent and folder sizes walk every file on the appliance, so total work
  grows as N² (#2759). By-type is cached between events since #1780, for listings up to 2,048 files.
- **The filename index lives in the heap** and is scanned linearly (#2760). A folder delete or move now reaches
  its contents in one step (#2754), and a search checks access before it reads anything about a match from disk
  and stops at 500 (#2758).
- **Uncached HEIC view conversion** goes away with #2378.
- **Unbounded tables, upload sessions and
  access log** (#2756); **deflate on already-compressed zips, uncapped** (#2757); **bcrypt on every Basic-auth
  request** (#2765).

## Fixed in this audit

| Issue | Defect | Test |
| --- | --- | --- |
| #2749 | `healthutil.Collector` read and wrote its CPU high-since marker with no lock | `TestCurrentHealth_ConcurrentCallers` (race) |
| #2750 | `/health` read the host on every call and queued under load | `TestCurrentHealth_ReusesARecentSample`, `TestCurrentHealth_ConcurrentCallersShareOneRead`, `TestCurrentHealth_CallersGetTheirOwnSlices` |
| #2751 | the backup job store shared one `*BackupJob` between the running snapshot and status reads | `TestInMemoryBackupJobStore_ReadDuringRun` (race) |
| #2752 | RAW converters ran without a timeout while holding an IO-semaphore slot | `TestRawViaDcraw_HungToolReturns` |
| #2755 | the server and the tailnet proxy had no header or idle timeout and spoke only HTTP/1.1; the proxy kept 2 idle loopback connections | `TestNewHTTPServer_ClosesStalledHeaders`, `TestNewHTTPServer_ClosesStalledTLSHandshake`, `TestNewHTTPServer_ClosesIdleKeepAlive`, `TestNewHTTPServer_SlowBodyOutlivesHeaderTimeout`, `TestNewHTTPServer_OffersHTTP2OverTLS`, `TestNewProxy_KeepsEnoughIdleConnections` |
| #2761 | nothing set a Go memory limit or a cgroup ceiling; the OOM killer was the only backstop | `TestApplyGoLimit_DerivesFromRAM`, `TestApplyGoLimit_EnvWins`, `TestInstallDropIn_WritesCeilingAndReloads`, `TestInstallDropIn_Idempotent`, `TestInstallDropIn_FollowsTheRAM`, `TestInstallDropIn_SkipsWithoutSystemd` |
| #2762 | images were decoded with no pixel cap, a thumbnail's EXIF rotation copied the full-size image, and backup copies held the same 8 slots as decodes | `TestDecodeImage_RefusesPixelsOverTheCap`, `TestThumbnailPaths_RefusePixelsOverTheCap`, `TestGetThumbnail_ImageOverPixelCapIsNotFound`, `TestUprightThumbnailMatchesRotatingFirst`, `TestUprightThumbnailDoesNotCopyTheSource`, `TestUprightDHashMatchesRotatedImage`, `TestOrientationTransformsHandleSubImages`, `TestNew_ClassesAreIsolated`, `TestClassSlots_FollowCPUs` |

`go test -race` over `./pkg/...`, `./internal/db/...`, `./internal/server/...` and the API packages reported no
other race; the existing tests rarely run these paths concurrently, which is why the #2749–#2752 fixes above needed their own.

## Recommendations, ranked

1. **Give reads a pool and stop writing per request** (#2766). Measured 4× at 500 clients and the difference
   between a wedge and 1,335 req/s at 2,000. Keep `synchronous=FULL` with WAL unless [durability](durability.md)
   is revisited; on this host, where flushes are cheap, it measured the same as `NORMAL`.
2. **Refresh only for the folder on screen, debounce, and jitter reconnects** (#2763), then **reload per-socket
   state only for the accounts a change concerns and encode each event once** (#2764). Together these remove the
   N² request storm that sets the limit once (1) is done.
3. **Never drop events for internal subscribers** (#2753). A correctness bug at any N.
4. **Replace whole-tree walks with an indexed, paged query and move the filename index out of the heap** (#2759,
   #2760). These set the limit past ~1,000 accounts, by file count rather than by request rate.
5. **Bound folder zips** (#2757) and drop server-side HEIC conversion (#2378).
6. **Prune and cap what grows** (#2756) and **stop running bcrypt per Basic-auth request** (#2765).
7. **Measure on a board.** The last open item of #2507: run the harness against an A55 board before and after (1)
   (`go test -tags stress ./internal/server/stress/` with `QUARK_BASE_URL`, `QUARK_USER` and `QUARK_PASSWORD`
   pointing at it, from a separate machine so the harness does not share its CPU), and replace the scaled
   estimates above.
