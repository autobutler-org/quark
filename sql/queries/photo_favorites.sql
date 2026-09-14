-- name: AddFavorite :exec
INSERT INTO
    photo_favorites (device_serial, rel_path)
VALUES
    (?, ?)
ON CONFLICT (device_serial, rel_path) DO NOTHING;

-- name: RemoveFavorite :exec
DELETE FROM photo_favorites
WHERE
    device_serial = ?
    AND rel_path = ?;

-- DeleteFavoritesUnder drops the favorite for a deleted path, and every
-- favorite under it when the path is a folder.
-- name: DeleteFavoritesUnder :exec
DELETE FROM photo_favorites
WHERE
    device_serial = sqlc.arg(device_serial)
    AND (
        rel_path = sqlc.arg(rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(rel_path)) + 1) = sqlc.arg(rel_path) || '/'
    );

-- MoveFavorites points favorites at a moved file or folder. OR IGNORE skips
-- a row whose destination is already a favorite; DeleteFavoritesUnder on the
-- old path clears those leftovers.
-- name: MoveFavorites :exec
UPDATE OR IGNORE photo_favorites
SET
    device_serial = sqlc.arg(new_device_serial),
    rel_path = sqlc.arg(new_rel_path) || substr(rel_path, length(CAST(sqlc.arg(old_rel_path) AS TEXT)) + 1)
WHERE
    device_serial = sqlc.arg(old_device_serial)
    AND (
        rel_path = sqlc.arg(old_rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(old_rel_path)) + 1) = sqlc.arg(old_rel_path) || '/'
    );

-- name: IsFavorite :one
SELECT
    COUNT(*) > 0
FROM
    photo_favorites
WHERE
    device_serial = ?
    AND rel_path = ?;

-- name: ListFavorites :many
SELECT
    *
FROM
    photo_favorites
ORDER BY
    created_at DESC;

-- name: CreateFavoritesAlbum :one
INSERT INTO
    photo_albums (name, smart_type)
VALUES
    ('Favorites', 'favorites')
RETURNING *;

-- name: GetFavoritesAlbum :one
SELECT
    *
FROM
    photo_albums
WHERE
    smart_type = 'favorites'
LIMIT
    1;


