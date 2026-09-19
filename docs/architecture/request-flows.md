# Request flows

The paths below cover most of what the backend does at runtime. Each diagram names the package that owns each
step, so it doubles as a map for where to start reading.

## Sign-in and an authenticated request

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant App as Flutter app<br/>AuthService
    participant MW as middleware
    participant H as api/v0/auth
    participant A as authutil
    participant DB as quark.db

    U->>App: username + password
    App->>MW: POST /api/v0/auth/login
    MW->>MW: auth rate limiter (per client IP)
    MW->>H: exempt path, no session needed
    H->>A: Login(params)
    A->>DB: users, verify password hash
    A->>DB: insert sessions row
    A-->>H: token
    H-->>App: 200 + token (+ session cookie)
    App->>App: store token in AppSettings

    App->>MW: GET /api/v0/files?path=… (Authorization: Bearer)
    MW->>DB: session lookup, account enabled?
    MW->>H: handler with deps in context
    Note over H: accessutil.Load(principal) once,<br/>then check every path in memory
```

## Streaming upload (resumable, chunked)

Large files use an upload session, so a dropped connection resumes instead of restarting and no chunk is ever
held whole in memory.

```mermaid
sequenceDiagram
    autonumber
    participant App as UploadManager<br/>ResumableUploadService
    participant H as api/v0/files
    participant U as uploadutil.SessionStore
    participant V as vfs (StorageServiceVFS)
    participant Bus as eventbus
    participant Idx as content indexer

    App->>H: POST /files/upload-session (path, size)
    H->>U: create session, staging file on the target device
    H-->>App: session id
    loop each chunk
        App->>H: PUT /files/upload-session/{id} (offset)
        H->>U: io.Copy request body → staging file
        H-->>App: bytes received
    end
    H->>V: MoveFileIn(staging → final path)
    Note over V: rename, not copy: a 4 GiB file is never written twice
    H->>Bus: publish upload
    Bus-->>Idx: index text content (FTS5)
    Bus-->>App: event over WebSocket
```

Small files take `POST /files/upload`, which streams the multipart body straight into `vfs.Write`. An abandoned
session is swept by the upload-session sweeper.

## Live events

```mermaid
sequenceDiagram
    autonumber
    participant App as EventsService
    participant H as api/v0/events
    participant Bus as eventbus
    participant Acc as accessutil
    participant P as any mutating handler

    App->>H: GET /api/v0/events (WebSocket upgrade, ?token=)
    H->>Bus: subscribe
    P->>Bus: Publish(move, path, newPath)
    Bus->>H: event
    H->>Acc: may this user read path?
    alt readable (or admin)
        H-->>App: JSON FileEvent
        App->>App: controllers refresh the affected view
    else not readable
        H->>H: drop
    end
    Note over H: account_changed for a disabled user closes the socket
```

## Background job (video transcode)

```mermaid
stateDiagram-v2
    [*] --> pending: POST /videos/transcode
    pending --> running: lane has capacity
    running --> completed: ffmpeg finished, output written
    running --> failed: error or server shutdown
    pending --> canceled: DELETE /jobs/:id
    running --> canceled: DELETE /jobs/:id
    failed --> pending: POST /jobs/:id/retry
    completed --> [*]
    canceled --> [*]
```

A job is a row in the `jobs` table, so history survives a restart. Every transition publishes a `job_*` event;
`GET /api/v0/jobs` remains the source of truth for the Jobs page.

## Vault unlock

```mermaid
sequenceDiagram
    autonumber
    participant App as VaultService
    participant MW as middleware
    participant H as api/v0/vault (admin)
    participant C as vaultcrypto.VaultSession
    participant VDB as vault tables<br/>(quark.db or vault.db)

    App->>MW: POST /vault/unlock (master password)
    MW->>MW: vault rate limiter, 1 attempt per 2 s per IP
    MW->>H: admin only
    H->>VDB: vault_config (salt, encrypted check value)
    H->>C: Argon2id derive key, decrypt check value, hold key in memory
    H-->>App: unlocked
    Note over C,VDB: drive unplugged → device monitor locks the session<br/>and publishes vault_device_disconnected
```
