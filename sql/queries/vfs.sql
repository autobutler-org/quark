-- Queries behind pkg/vfs: vfs_metadata (SQLiteMetadataStore) and
-- vfs_db_entries (DBVFS).
--
-- A descendant of a directory is matched with substr rather than LIKE, so a
-- '%' or '_' in a name is not a wildcard. prefix is "dir/", and its length is
-- taken here because substr counts characters where Go's len counts bytes.

-- name: ListVFSMetadata :many
SELECT
    key,
    value
FROM
    vfs_metadata
WHERE
    namespace = ?
    AND path = ?;

-- name: UpsertVFSMetadata :exec
INSERT INTO
    vfs_metadata (namespace, path, key, value, updated_at)
VALUES
    (?, ?, ?, ?, datetime('now'))
ON CONFLICT (namespace, path, key) DO UPDATE SET
    value = excluded.value,
    updated_at = excluded.updated_at;

-- name: DeleteVFSMetadataKey :exec
DELETE FROM vfs_metadata
WHERE
    namespace = ?
    AND path = ?
    AND key = ?;

-- name: ListVFSMetadataPathsByKey :many
SELECT
    path
FROM
    vfs_metadata
WHERE
    namespace = ?
    AND key = ?
ORDER BY
    path;

-- name: ListVFSMetadataPathsByKeyValue :many
SELECT
    path
FROM
    vfs_metadata
WHERE
    namespace = ?
    AND key = ?
    AND value = ?
ORDER BY
    path;

-- name: ListDBVFSEntriesUnder :many
SELECT
    path,
    is_dir,
    size,
    mime_type,
    updated_at
FROM
    vfs_db_entries
WHERE
    namespace = sqlc.arg(namespace)
    AND substr(path, 1, length(CAST(sqlc.arg(prefix) AS TEXT))) = CAST(sqlc.arg(prefix) AS TEXT)
    AND path != sqlc.arg(dir)
ORDER BY
    path;

-- name: GetDBVFSEntry :one
SELECT
    is_dir,
    size,
    mime_type,
    updated_at
FROM
    vfs_db_entries
WHERE
    namespace = ?
    AND path = ?;

-- name: GetDBVFSEntryContent :one
SELECT
    is_dir,
    content
FROM
    vfs_db_entries
WHERE
    namespace = ?
    AND path = ?;

-- A directory already at the path is left alone and reports no rows.
-- name: UpsertDBVFSFile :execrows
INSERT INTO
    vfs_db_entries (namespace, path, is_dir, size, mime_type, content, updated_at)
VALUES
    (?, ?, 0, ?, ?, ?, datetime('now'))
ON CONFLICT (namespace, path) DO UPDATE SET
    size = excluded.size,
    mime_type = excluded.mime_type,
    content = excluded.content,
    updated_at = excluded.updated_at
WHERE
    is_dir = 0;

-- Anything already at the path is left alone and reports no rows.
-- name: InsertDBVFSFileIfAbsent :execrows
INSERT INTO
    vfs_db_entries (namespace, path, is_dir, size, mime_type, content, updated_at)
VALUES
    (?, ?, 0, ?, ?, ?, datetime('now'))
ON CONFLICT (namespace, path) DO NOTHING;

-- name: InsertDBVFSDirIfAbsent :exec
INSERT OR IGNORE INTO
    vfs_db_entries (namespace, path, is_dir, size, mime_type, content)
VALUES
    (?, ?, 1, 0, '', NULL);

-- name: CountDBVFSEntriesUnder :one
SELECT
    COUNT(1)
FROM
    vfs_db_entries
WHERE
    namespace = sqlc.arg(namespace)
    AND substr(path, 1, length(CAST(sqlc.arg(prefix) AS TEXT))) = CAST(sqlc.arg(prefix) AS TEXT)
    AND path != sqlc.arg(dir);

-- name: DeleteDBVFSEntry :execrows
DELETE FROM vfs_db_entries
WHERE
    namespace = ?
    AND path = ?;

-- name: DeleteDBVFSEntryTree :execrows
DELETE FROM vfs_db_entries
WHERE
    namespace = sqlc.arg(namespace)
    AND (
        path = sqlc.arg(path)
        OR substr(path, 1, length(CAST(sqlc.arg(prefix) AS TEXT))) = CAST(sqlc.arg(prefix) AS TEXT)
    );

-- Renames src and every descendant of it to sit under dst.
-- name: MoveDBVFSEntryTree :exec
UPDATE vfs_db_entries
SET
    path = CAST(sqlc.arg(dst) AS TEXT) || substr(path, length(CAST(sqlc.arg(src) AS TEXT)) + 1)
WHERE
    namespace = sqlc.arg(namespace)
    AND (
        path = CAST(sqlc.arg(src) AS TEXT)
        OR substr(path, 1, length(CAST(sqlc.arg(prefix) AS TEXT))) = CAST(sqlc.arg(prefix) AS TEXT)
    );
