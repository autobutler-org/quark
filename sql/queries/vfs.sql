-- Queries behind pkg/vfs: vfs_metadata (SQLiteMetadataStore).

-- name: ListVFSMetadata :many
SELECT
    key,
    value
FROM
    vfs_metadata
WHERE
    namespace = sqlc.arg(namespace)
    AND path = sqlc.arg(path);

-- name: UpsertVFSMetadata :exec
INSERT INTO
    vfs_metadata (namespace, path, key, value, updated_at)
VALUES
    (sqlc.arg(namespace), sqlc.arg(path), sqlc.arg(key), sqlc.arg(value), strftime('%Y-%m-%d %H:%M:%f', 'now'))
ON CONFLICT (namespace, path, key) DO UPDATE SET
    value = excluded.value,
    updated_at = excluded.updated_at;

-- name: DeleteVFSMetadataKey :exec
DELETE FROM vfs_metadata
WHERE
    namespace = sqlc.arg(namespace)
    AND path = sqlc.arg(path)
    AND key = sqlc.arg(key);

-- name: ListVFSMetadataPathsByKey :many
SELECT
    path
FROM
    vfs_metadata
WHERE
    namespace = sqlc.arg(namespace)
    AND key = sqlc.arg(key)
ORDER BY
    path;

-- name: ListVFSMetadataPathsByKeyValue :many
SELECT
    path
FROM
    vfs_metadata
WHERE
    namespace = sqlc.arg(namespace)
    AND key = sqlc.arg(key)
    AND value = sqlc.arg(value)
ORDER BY
    path;
