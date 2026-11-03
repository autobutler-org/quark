-- name: CreateAlbum :one
INSERT INTO
    photo_albums (name, parent_id, user_id)
VALUES
    (
        sqlc.arg(name),
        sqlc.arg(parent_id),
        CAST(sqlc.arg(user_id) AS BIGINT)
    )
RETURNING *;

-- Album reads and writes are scoped to the owning account (#1912): another
-- account's album id reads as missing. The CAST keeps the nullable user_id
-- column (014) a plain id parameter.
-- name: GetAlbum :one
SELECT
    *
FROM
    photo_albums
WHERE
    id = sqlc.arg(id)
    AND user_id = CAST(sqlc.arg(user_id) AS BIGINT)
LIMIT
    1;

-- name: ListAlbums :many
SELECT
    *
FROM
    photo_albums
WHERE
    user_id = CAST(sqlc.arg(user_id) AS BIGINT)
ORDER BY
    parent_id NULLS FIRST,
    name;

-- name: ListRootAlbums :many
SELECT
    *
FROM
    photo_albums
WHERE
    user_id = CAST(sqlc.arg(user_id) AS BIGINT)
    AND parent_id IS NULL
ORDER BY
    name;

-- name: ListChildAlbums :many
SELECT
    *
FROM
    photo_albums
WHERE
    parent_id = sqlc.arg(parent_id)
ORDER BY
    name;

-- name: RenameAlbum :one
UPDATE photo_albums
SET
    name = sqlc.arg(name),
    updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE
    id = sqlc.arg(id)
    AND user_id = CAST(sqlc.arg(user_id) AS BIGINT)
RETURNING *;

-- name: MoveAlbum :one
UPDATE photo_albums
SET
    parent_id = sqlc.arg(parent_id),
    updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE
    id = sqlc.arg(id)
    AND user_id = CAST(sqlc.arg(user_id) AS BIGINT)
RETURNING *;

-- name: DeleteAlbum :exec
DELETE FROM photo_albums
WHERE
    id = sqlc.arg(id)
    AND user_id = CAST(sqlc.arg(user_id) AS BIGINT);

-- name: AddPhotoToAlbum :one
INSERT INTO
    photo_album_items (album_id, device_serial, rel_path)
VALUES
    (sqlc.arg(album_id), sqlc.arg(device_serial), sqlc.arg(rel_path))
ON CONFLICT (album_id, device_serial, rel_path) DO UPDATE
SET
    added_at = photo_album_items.added_at -- no-op; keeps RETURNING from returning nothing
RETURNING *;

-- name: RemovePhotoFromAlbum :exec
DELETE FROM photo_album_items
WHERE
    album_id = sqlc.arg(album_id)
    AND device_serial = sqlc.arg(device_serial)
    AND rel_path = sqlc.arg(rel_path);

-- DeletePhotoFromAllAlbums drops every album row for the path, and for
-- everything under it when the path is a folder. substr rather than LIKE, so a
-- '%' or '_' in a file name is not a wildcard.
-- name: DeletePhotoFromAllAlbums :exec
DELETE FROM photo_album_items
WHERE
    device_serial = sqlc.arg(device_serial)
    AND (
        rel_path = sqlc.arg(rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(rel_path)) + 1) = sqlc.arg(rel_path) || '/'
    );

-- MoveAlbumItems points album rows at a moved file, or at everything under a
-- moved folder. The count guard skips a row whose destination the album already
-- holds; DeletePhotoFromAllAlbums on the old path clears those leftovers.
-- It replaces UPDATE OR IGNORE, which PostgreSQL has no form of. COUNT(*) = 0
-- and not NOT EXISTS: sqlc v1.30.0's SQLite engine leaves a parameter under a
-- NOT unexpanded (sqlc-dev/sqlc#4110; v1.31.1 expands it).
-- name: MoveAlbumItems :exec
UPDATE photo_album_items
SET
    device_serial = sqlc.arg(new_device_serial),
    rel_path = sqlc.arg(new_rel_path) || substr(photo_album_items.rel_path, length(CAST(sqlc.arg(old_rel_path) AS TEXT)) + 1)
WHERE
    photo_album_items.device_serial = sqlc.arg(old_device_serial)
    AND (
        photo_album_items.rel_path = sqlc.arg(old_rel_path)
        OR substr(photo_album_items.rel_path, 1, length(sqlc.arg(old_rel_path)) + 1) = sqlc.arg(old_rel_path) || '/'
    )
    AND (
        SELECT
            COUNT(*)
        FROM
            photo_album_items AS held
        WHERE
            held.album_id = photo_album_items.album_id
            AND held.device_serial = sqlc.arg(new_device_serial)
            AND held.rel_path = sqlc.arg(new_rel_path) || substr(photo_album_items.rel_path, length(CAST(sqlc.arg(old_rel_path) AS TEXT)) + 1)
    ) = 0;

-- name: ListAlbumItems :many
SELECT
    *
FROM
    photo_album_items
WHERE
    album_id = sqlc.arg(album_id)
ORDER BY
    added_at DESC;

-- name: CountAlbumItems :one
SELECT
    COUNT(*)
FROM
    photo_album_items
WHERE
    album_id = sqlc.arg(album_id);

-- ListAlbumsContainingPhoto lists the albums of one account that hold a photo.
-- name: ListAlbumsContainingPhoto :many
SELECT
    pa.*
FROM
    photo_albums pa
    JOIN photo_album_items pai ON pa.id = pai.album_id
WHERE
    pa.user_id = CAST(sqlc.arg(user_id) AS BIGINT)
    AND pai.device_serial = sqlc.arg(device_serial)
    AND pai.rel_path = sqlc.arg(rel_path)
ORDER BY
    pa.name;
