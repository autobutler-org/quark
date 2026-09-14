-- name: CreateAlbum :one
INSERT INTO
    photo_albums (name, parent_id)
VALUES
    (?, ?)
RETURNING *;

-- name: GetAlbum :one
SELECT
    *
FROM
    photo_albums
WHERE
    id = ?
LIMIT
    1;

-- name: ListAlbums :many
SELECT
    *
FROM
    photo_albums
ORDER BY
    parent_id,
    name;

-- name: ListRootAlbums :many
SELECT
    *
FROM
    photo_albums
WHERE
    parent_id IS NULL
ORDER BY
    name;

-- name: ListChildAlbums :many
SELECT
    *
FROM
    photo_albums
WHERE
    parent_id = ?
ORDER BY
    name;

-- name: RenameAlbum :one
UPDATE photo_albums
SET
    name = ?,
    updated_at = datetime('now')
WHERE
    id = ?
RETURNING *;

-- name: MoveAlbum :one
UPDATE photo_albums
SET
    parent_id = ?,
    updated_at = datetime('now')
WHERE
    id = ?
RETURNING *;

-- name: DeleteAlbum :exec
DELETE FROM photo_albums
WHERE
    id = ?;

-- name: AddPhotoToAlbum :one
INSERT INTO
    photo_album_items (album_id, device_serial, rel_path)
VALUES
    (?, ?, ?)
ON CONFLICT (album_id, device_serial, rel_path) DO UPDATE
SET
    added_at = added_at -- no-op; keeps RETURNING from returning nothing
RETURNING *;

-- name: RemovePhotoFromAlbum :exec
DELETE FROM photo_album_items
WHERE
    album_id = ?
    AND device_serial = ?
    AND rel_path = ?;

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
-- moved folder. OR IGNORE skips a row whose destination the album already
-- holds; DeletePhotoFromAllAlbums on the old path clears those leftovers.
-- name: MoveAlbumItems :exec
UPDATE OR IGNORE photo_album_items
SET
    device_serial = sqlc.arg(new_device_serial),
    rel_path = sqlc.arg(new_rel_path) || substr(rel_path, length(CAST(sqlc.arg(old_rel_path) AS TEXT)) + 1)
WHERE
    device_serial = sqlc.arg(old_device_serial)
    AND (
        rel_path = sqlc.arg(old_rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(old_rel_path)) + 1) = sqlc.arg(old_rel_path) || '/'
    );

-- name: ListAlbumItems :many
SELECT
    *
FROM
    photo_album_items
WHERE
    album_id = ?
ORDER BY
    added_at DESC;

-- name: CountAlbumItems :one
SELECT
    COUNT(*)
FROM
    photo_album_items
WHERE
    album_id = ?;

-- name: ListAlbumsContainingPhoto :many
SELECT
    pa.*
FROM
    photo_albums pa
    JOIN photo_album_items pai ON pa.id = pai.album_id
WHERE
    pai.device_serial = ?
    AND pai.rel_path = ?
ORDER BY
    pa.name;
