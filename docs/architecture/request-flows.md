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

A session may be opened with the file's `sha256`. The last chunk then streams the staging file through SHA-256
before the move: a match completes and returns the hash, and a mismatch is a `422` that ends the session, so a
file that fails the check never lands and no event is published for it.

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
    running --> completed: remux finished, output written
    running --> failed: error
    running --> pending: server shutdown, or its instance died
    pending --> canceled: DELETE /jobs/:id
    running --> canceled: DELETE /jobs/:id
    failed --> pending: POST /jobs/:id/retry
    completed --> [*]
    canceled --> [*]
```

A job is a row in the `jobs` table, so history survives a restart. A running row names the instance that owns
it, which keeps it with a heartbeat, so several instances can share the queue. Every transition publishes a `job_*` event;
`GET /api/v0/jobs` remains the source of truth for the Jobs page.

## Vault unlock

Each account's vault is end-to-end encrypted (#3456). The Quark stores the account's vault key only wrapped and
every item only as ciphertext, so unlocking is work the app does; the Quark serves bytes it cannot open.

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant App as VaultController<br/>AccountCrypto
    participant H as api/v0/vault<br/>(signed-in, not admin)
    participant V as vaultutil
    participant DB as vault_keys · vault_items

    App->>H: GET /vault/key
    H->>V: GetKey(caller's user id)
    V->>DB: the caller's row only
    H-->>App: wrapped key + kdfParams, or 404 (no vault yet: offer setup)
    U->>App: login password
    App->>App: Argon2id over the auth salt, HKDF "vault-wrap",<br/>open the wrapped key (a wrong password sends nothing)
    App->>H: GET /vault/items
    H-->>App: the caller's items: ciphertext, nonce, formatVersion
    App->>App: XChaCha20-Poly1305 open each item in memory
    Note over App: search, folders, import and export run on the decrypted items.<br/>Lock, 15 min idle or sign-out forgets the key
```

Setup is the same in reverse: the app makes a random 32-byte key, wraps it under the password's `vault-wrap` key,
and under the recovery phrase's `recovery-vault-wrap` key when the user typed the phrase at setup, and stores it
with `PUT /vault/key`. That request carries the password's auth key as `password`, which the Quark re-confirms
first (403 for any other password, under the sign-in rate limit), so the key is only ever wrapped under the login
password. It refuses a second key with 409, so a vault's key is never replaced, only re-wrapped. A password change, a recovery and a new recovery phrase send the key re-wrapped as `vaultKey` in
`PUT /auth/password`, `POST /auth/recover` and `PUT /auth/recovery-key`, in the same transaction as the credential
(`POST /auth/recover/vault-key` hands a recovery the wrapped key first). Every write publishes `vault_changed`,
which `accessutil.FilterEvent` delivers only to the account whose vault it is, so its other sessions read the
vault again. `DELETE /vault` removes the key and every item, the way out for a vault nothing opens any more. It
re-confirms the login password's auth key the same way, under the same rate limit, so a session alone cannot wipe
a vault (#3615).
