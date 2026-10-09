# Data

Files are the primary data and live on disk. SQLite holds only what cannot: identity, grants, collections, job
history, and indexes. The rule in `AGENTS.md` is to reach for the database last.

## Where state lives

```mermaid
flowchart LR
    subgraph datadir["Data dir (storageutil.GetDataDir)"]
        mainDb[("quark.db<br/>main schema, migrated")]
        healthDb[("quark.health.db<br/>system metrics")]
        files[/"files/<br/>user files, per-user homes"/]
        tls[/"self-signed cert + key"/]
    end
    tailscaleState[/"tsnet state<br/>/var/lib/quark/tsnet on Linux"/]
    subgraph usb["Each managed USB drive"]
        driveFiles[/"files + trash"/]
        vaultDb[("vault.db<br/>only if the vault was moved here")]
        snapshots[/"backup snapshots"/]
    end
    mainDb -- "vault_location = serial" --> vaultDb
```

| Store              | Opened by                         | Schema source                             |
| ------------------ | --------------------------------- | ----------------------------------------- |
| `quark.db`         | `db.ConnectToDatabase`            | `internal/db/migrations` (golang-migrate) |
| `quark.health.db`  | `db.ConnectToHealthDatabase`      | raw, owned by `healthutil`                |
| `vault.db`         | `db.ConnectToVaultDatabase`       | `internal/db/vault_schema.go`             |

All three use the pure-Go `modernc.org/sqlite` driver, so the binary cross-compiles without cgo.

## Main schema

Tables are grouped by the migration that introduced them. Queries live in `sql/queries/*.sql` and are generated
into `internal/db/*.sql.go` by sqlc, which type-checks them against the migrations.

```mermaid
erDiagram
    users ||--o{ sessions : "signs in with"
    users ||--o{ group_members : "belongs to"
    groups ||--o{ group_members : has
    users ||--o{ path_access : "granted (user_id)"
    groups ||--o{ path_access : "granted (group_id)"
    photo_albums ||--o{ photo_albums : "parent_id"
    photo_albums ||--o{ photo_album_items : contains
    file_content ||--|| file_content_fts : "FTS5 external content"

    users { int id  string username  bool is_admin  string status }
    sessions { string token  int user_id  datetime expires_at  datetime last_used_at }
    groups { int id  string name  bool builtin }
    group_members { int group_id  int user_id }
    path_access { string device_serial  string rel_path  int user_id  int group_id  string level }
    photo_albums { int id  int parent_id  string name  string smart_type }
    photo_album_items { int album_id  string device_serial  string rel_path }
    photo_favorites { string device_serial  string rel_path }
    photo_rotations { string device_serial  string rel_path  int rotation_quarters }
    photo_hashes { string device_serial  string rel_path  string dhash  string content_hash }
    file_content { string serial  string rel_path  string extracted }
    jobs { int id  string kind  string status  string lane  real progress  int attempts }
    connected_devices { string ip_address  string user_agent  datetime last_seen_at }
    device_names { string device_serial  string display_name }
    vfs_metadata { string namespace  string path  string key  string value }
    vfs_db_entries { string namespace  string path  bool is_dir  blob content }
```

Column lists are abbreviated to what explains a relationship; the migration files are authoritative. Files are
always addressed as `(device_serial, rel_path)`, never by a database id, so moving bytes on disk never needs a
join. `path_access.level` is `read`, `write` or `owner`, and each row names exactly one of a user or a group
(the built-in `everyone` group is seeded by the migration).

| Migration              | Tables                                                                  |
| ---------------------- | ----------------------------------------------------------------------- |
| `001_auth`             | `users`, `sessions`                                                     |
| `002_storage_devices`  | `device_names`, `device_roles`                                          |
| `003_connected_devices`| `connected_devices`                                                     |
| `004_photos`           | `photo_albums`, `photo_album_items`, `photo_rotations`, `photo_favorites`, `photo_hashes` |
| `005_vault`            | `vault_config`, `vault_folders`, `vault_entries`, `vault_location`      |
| `006_file_search`      | `file_content`, `file_content_fts` (FTS5)                               |
| `007_vfs`              | `vfs_metadata`, `vfs_db_entries`                                        |
| `008_unique_album_names` | constraint only                                                       |
| `009_jobs`             | `jobs`                                                                  |
| `010_path_access`      | `groups`, `group_members`, `path_access`                                |
| `011_user_status`      | column change on `users`                                                |
| `012_group_name_nocase`| case-insensitive unique `groups.name`                                   |
| `013_job_owner`        | column change on `jobs`                                                 |
| `014_per_user_photos`  | owner column on `photo_albums`, `photo_favorites`                       |
| `021_calendar`         | `calendars` (one default, Personal), `calendar_events`                  |
| `022_calendar_event_owner` | owner column on `calendar_events`                                   |

Migrations are numbered, gap-free and paired; `make check/migrations` fails a PR whose number is at or below
`main`'s highest, because golang-migrate would silently skip it on upgraded devices.

## Access control

`accessutil` answers "may this principal reach this path?". Grants are keyed by `(device serial, canonical
path)` and are additive down the tree: a path's level is the highest level granted on it or any ancestor.
Admins bypass the table, so a path with no grant is admin-only. Every account gets a home directory and an owner
grant on it; `repairHomes` restores that at startup for accounts that predate it.

```mermaid
flowchart TD
    q{{"can user read /photos/2024/a.jpg<br/>on device S?"}} --> adm{admin?}
    adm -- yes --> allow([allow])
    adm -- no --> load["Load(principal): user + group rows, once per request"]
    load --> walk["walk /photos/2024/a.jpg → /photos/2024 → /photos → /"]
    walk --> max["highest level granted on any ancestor"]
    max --> cmp{"≥ read?"}
    cmp -- yes --> allow
    cmp -- no --> deny([deny / filter out])
```

## Virtual filesystem

`pkg/vfs` puts one interface over every place bytes can live. Handlers and services ask the registry for a
namespace. The server registers one per managed device: `files` for the internal drive and `files:<serial>` for
each USB drive (`vfs.FilesNamespace`), each a `StorageServiceVFS` rooted at that device's files directory. The
storage service finds the devices; it has no file operations of its own, and the disk work behind a device
namespace (listing, walking, moving, the trash) is private to `pkg/vfs`.

```mermaid
classDiagram
    class VFS {
        <<interface>>
        List(ctx, path, filter) []FileInfo
        Stat(ctx, path) FileInfo
        Open(ctx, path) File
        Write(ctx, path, io.Reader, opts)
        Delete(ctx, path, opts)
        MkdirAll(ctx, path)
        Move(ctx, src, dst)
        Copy(ctx, src, dst, opts)
        Watch(ctx, path) chan WatchEvent
    }
    class HostPather {
        <<interface>>
        HostPath(ctx, path) string
    }
    class FileMover {
        <<interface>>
        MoveFileIn(ctx, srcAbs, path, opts)
    }
    class Trasher {
        <<interface>>
        Trash(ctx, paths, opts) []TrashedItem
        ListTrash(ctx) []TrashItem
        RestoreTrash(ctx, refs) []RestoredItem
        DeleteTrash(ctx, refs) []string
    }
    class Registry {
        Register(Namespace, VFS)
        Get(id) VFS
    }
    class MetadataStore {
        <<interface>>
        per-path JSON metadata
    }
    VFS <|.. LocalVFS : host directory
    VFS <|.. MemVFS : tests
    VFS <|.. DBVFS : vfs_db_entries
    VFS <|.. StorageServiceVFS : managed devices
    HostPather <|.. LocalVFS
    HostPather <|.. StorageServiceVFS
    FileMover <|.. LocalVFS
    FileMover <|.. StorageServiceVFS
    Trasher <|.. StorageServiceVFS
    Registry o-- VFS
    MetadataStore <|.. SQLiteMetadataStore : vfs_metadata
```

Every implementation keeps one contract, which `pkg/vfs/conformance_test.go` holds them to:

- `Open` returns a `vfs.File` — a reader that also seeks and reads at an offset — so range requests, zip listing
  and image decoding take it directly. The disk-backed namespaces hand back an `*os.File`.
- Paths are relative and slash-separated, with no leading or trailing slash: `accessutil.Canonical`'s form.
- `Stat` and `Open` return `ErrNotFound` only for a path that does not exist; a permission failure is
  `ErrPermissionDenied`, and `Open` on a directory is `ErrIsDirectory`.
- `Write` with `IfNoneMatch: "*"` refuses a taken name with `ErrConflict`, atomically, so two racing writers
  cannot both win. `Copy` within a namespace and `vfs.CopyBetween` across two stream through that same write
  path, so a copy is never visible half-written.
- `Delete` of a non-empty directory without `Recursive` is `ErrNotEmpty`.
- `HostPather` gives a host-backed namespace's path to an external process (dcraw, exiftool, ffmpeg) or to
  symlink resolution. It is never a way around `Open`.
- `Trasher` is the trash of a device namespace. A user delete moves an item there; `Delete` stays the permanent
  removal. A trashed item keeps an address, `.trash/<trash name>/...`, which `Stat`, `Open` and `HostPath`
  resolve into the trash beside the device's files directory.

## The vault

The vault is an encrypted store for secrets. Its tables (`vault_config`, `vault_folders`, `vault_entries`) live
in `quark.db` by default; when the admin moves the vault to a USB drive, `vault_location` records that drive's
serial and the same tables are created in `vault.db` on the drive (`internal/db/vault_schema.go`). Unlocking
derives a key from the master password with Argon2id, checks it by decrypting a known verification value, and
holds the key in `vaultcrypto.VaultSession` memory only. Unplugging the drive locks the session. `pkg/backup`
exports the vault to another device and imports it back.
