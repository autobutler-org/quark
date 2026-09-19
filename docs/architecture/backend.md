# Backend

The backend is one Go module (`github.com/autobutler-org/quark`) built on gin. Its layering is strict: a
handler never touches SQL or the filesystem directly, and business logic never sees a `*gin.Context`.

## Layers

```mermaid
flowchart TB
    subgraph http["HTTP layer — internal/server"]
        mw["middleware/<br/>rate limit · inject deps · auth · device tracking"]
        routes["routes.go<br/>mounts every router under /api/v0"]
        handlers["api/v0/&lt;segment&gt;/<br/>one handler per file"]
        admin["RequireAdmin group<br/>admin · vault · settings · storage · version · devices"]
    end

    subgraph logic["Business logic — pkg/util/*util"]
        files["fileutil · uploadutil · searchutil"]
        media["photoutil · albumutil · videoutil<br/>thumbnailutil · transcodeutil · ffmpegutil"]
        auth["authutil · accessutil"]
        ops["storageutil · jobutil · workerutil<br/>settingsutil · updateutil · remoteutil"]
        vault["vaultutil · vaultcrypto"]
        bus["eventbus"]
    end

    subgraph infra["Infrastructure"]
        vfs["pkg/vfs<br/>VFS registry + metadata"]
        db["internal/db<br/>sqlc queries + migrations"]
        backup["pkg/backup"]
    end

    disk[("Disk / USB drives")]
    sqlite[("SQLite")]

    mw --> routes --> handlers
    routes --> admin --> handlers
    handlers --> files & media & auth & ops & vault
    files & media --> vfs
    files & media & auth & ops & vault --> db
    ops --> backup
    files & media & ops --> bus
    vfs --> disk
    vfs --> sqlite
    db --> sqlite
    backup --> disk
```

The handler contract, from `AGENTS.md`:

1. Pull `deps` out of the request context: `ctxutil.Get[deputil.Dependencies](c, "deps")`.
2. Parse the request into a `pkg/util` `…Params` struct and call the service.
3. Return a `*serverutil.Response` (`Ok().WithData(…)`, `InternalServerError(err)`, …); return `nil` only when the
   handler streamed the response itself.

Directory names match URL segments (`/api/v0/albums/*` → `api/v0/albums/`), packages are named `v0_<segment>`,
and `scripts/check-go-structure.bash` enforces the file layout.

## Dependency graph

`deputil.Dependencies` is the single object every layer receives. `NewDependencies()` builds an empty graph with
the always-present pieces (rate limiters, upload session store, backup job store); `DefaultDependencies()`
connects the real ones. Tests start from the empty graph and chain `With…` builders to inject fakes.

```mermaid
classDiagram
    class Dependencies {
        <<interface>>
        Database() DatabaseSqlc
        HealthDatabase() DatabaseRaw
        VaultDB() DatabaseSqlc
        StorageService() StorageService
        VFSRegistry() vfs.Registry
        MetadataStore() vfs.MetadataStore
        EventBus() eventbus.Bus
        JobQueue() jobutil.Queue
        Worker() workerutil.Worker
        FileIndex() storageutil.FileIndex
        UploadSessions() uploadutil.SessionStore
        VaultSession() vaultcrypto.VaultSession
        AuthRateLimiter() Limiter
        VaultRateLimiter() Limiter
        IOSemaphore() Semaphore
        BackupJobStore() BackupJobStore
    }
    Dependencies --> DatabaseSqlc : quark.db
    Dependencies --> DatabaseRaw : quark.health.db
    Dependencies --> StorageService : managed devices
    Dependencies --> Registry : namespace "files"
    Registry --> StorageServiceVFS
    StorageServiceVFS --> StorageService
    Dependencies --> Bus
    Dependencies --> Queue
    Queue --> DatabaseSqlc : jobs table
    Queue --> Bus : job_* events
```

## Middleware chain

`middleware.Use` runs before any route is registered, so every request passes through the same chain.

```mermaid
flowchart LR
    req([request]) --> rl{"rate limit<br/>auth paths 5 r/s<br/>vault unlock 0.5 r/s"}
    rl -- over --> r429([429])
    rl --> inject["inject deps<br/>into context"]
    inject --> authz{"requireAuth<br/>/api/* only"}
    authz -- "exempt path<br/>(setup, login, recover, status)" --> next
    authz -- "Bearer · cookie · Basic<br/>?token= on media paths" --> valid{"session valid<br/>& account enabled?"}
    valid -- no --> r401([401])
    valid -- yes --> next["track device"]
    next --> admin{"admin route?"}
    admin -- "yes, not admin" --> r403([403])
    admin -- ok --> handler[[handler]]
```

`?token=` is accepted only on paths where a header cannot be set (media streaming, downloads, the WebSocket).

## Startup

`server.StartServer` wires the background services before it opens the listener.

```mermaid
sequenceDiagram
    autonumber
    participant main as quark serve
    participant deps as DefaultDependencies
    participant s as StartServer
    participant bg as background workers
    participant gin as gin engine

    main->>deps: connect quark.db + quark.health.db, run migrations
    deps-->>main: storage service, VFS registry, event bus, job queue, vault session
    main->>s: StartServer(deps, opts)
    s->>s: remove stale update backups, register health collector
    s->>s: SetupFilesDir, repairHomes (every account gets a home + grant)
    s->>bg: worker, job queue (transcode handler), sync worker
    s->>bg: FileIndex.BuildAndWatch, content indexer + backfill
    s->>bg: vault device monitor (10 s), USB monitor (5 s)
    s->>bg: session purge (24 h), trash purge (1 h), upload-session sweeper
    s-->>bg: tsnet remote access, if enabled
    s->>gin: middleware.Use, setupRoutes, Swagger, SPA fallback
    s->>gin: listen on :443 (TLS 1.3) or :8080
```

## Background work

| Worker                 | Package                         | Trigger              | Effect                                                    |
| ---------------------- | ------------------------------- | -------------------- | --------------------------------------------------------- |
| Job queue              | `jobutil` + `transcodeutil`     | enqueued job rows    | runs video transcodes per lane, publishes `job_*` events  |
| Worker                 | `workerutil`                    | backup requests      | copies files to a backup device off the request path      |
| Sync worker            | `pkg/backup`                    | file events          | keeps snapshots on a backup device in sync                |
| File index             | `storageutil.FileIndex`         | fs watch + events    | in-memory index of files across managed devices          |
| Content indexer        | `internal/server/content_indexer.go` | upload / move / delete | FTS5 rows for text documents; backfill at startup  |
| USB monitor            | `server.usbDeviceMonitor`       | every 5 s            | auto-mounts new drives                                    |
| Vault device monitor   | `server.vaultDeviceMonitor`     | every 10 s           | locks the vault when its drive disappears                 |
| Session purge          | `authutil`                      | startup + 24 h       | deletes expired sessions                                  |
| Trash purge            | `storageutil` + `accessutil`    | startup + 1 h        | deletes expired trash and its access rows                 |
| Upload sweeper         | `uploadutil.SessionStore`       | interval             | removes abandoned chunked uploads                         |

## Event bus

`pkg/util/eventbus` is an in-process pub/sub. Publishers never block: a subscriber that falls behind drops
events, so clients treat events as a hint to refresh and the REST endpoints as the source of truth.

| Kind group | Kinds                                                                                     |
| ---------- | ----------------------------------------------------------------------------------------- |
| Files      | `upload`, `delete`, `move`, `new_folder`, `trash_changed`                                   |
| Jobs       | `job_queued`, `job_started`, `job_progress`, `job_completed`, `job_failed`, `job_canceled` |
| Backup     | `backup_started`, `backup_progress`, `backup_completed`, `backup_failed`                   |
| Vault      | `vault_device_disconnected`, `vault_device_reconnected`, `vault_storage_changed`           |
| Accounts   | `account_changed`, `access_changed`                                                       |
