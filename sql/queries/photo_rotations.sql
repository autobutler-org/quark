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
