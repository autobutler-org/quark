-- name: GetPhotoRotation :one
SELECT
    rotation_quarters
FROM
    photo_rotations
WHERE
    device_serial = sqlc.arg(device_serial)
    AND rel_path = sqlc.arg(rel_path)
LIMIT
    1;

-- name: UpsertPhotoRotation :exec
INSERT INTO
    photo_rotations (device_serial, rel_path, rotation_quarters, updated_at)
VALUES
    (sqlc.arg(device_serial), sqlc.arg(rel_path), sqlc.arg(rotation_quarters), strftime('%Y-%m-%d %H:%M:%f', 'now'))
ON CONFLICT (device_serial, rel_path) DO UPDATE SET
    rotation_quarters = excluded.rotation_quarters,
    updated_at = excluded.updated_at;

-- name: DeletePhotoRotation :exec
DELETE FROM photo_rotations
WHERE
    device_serial = sqlc.arg(device_serial)
    AND rel_path = sqlc.arg(rel_path);

-- DeletePhotoRotationsUnder drops the rotation of a deleted path, and of
-- every photo under it when the path is a folder.
-- name: DeletePhotoRotationsUnder :exec
DELETE FROM photo_rotations
WHERE
    device_serial = sqlc.arg(device_serial)
    AND (
        rel_path = sqlc.arg(rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(rel_path)) + 1) = sqlc.arg(rel_path) || '/'
    );

-- MovePhotoRotations points the rotations of a moved file or folder at its
-- new path. The caller clears the destination with DeletePhotoRotationsUnder
-- first, so no moved row collides with one already there.
-- name: MovePhotoRotations :exec
UPDATE photo_rotations
SET
    device_serial = sqlc.arg(new_device_serial),
    rel_path = sqlc.arg(new_rel_path) || substr(photo_rotations.rel_path, length(CAST(sqlc.arg(old_rel_path) AS TEXT)) + 1)
WHERE
    photo_rotations.device_serial = sqlc.arg(old_device_serial)
    AND (
        photo_rotations.rel_path = sqlc.arg(old_rel_path)
        OR substr(photo_rotations.rel_path, 1, length(sqlc.arg(old_rel_path)) + 1) = sqlc.arg(old_rel_path) || '/'
    );
