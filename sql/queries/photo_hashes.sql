-- name: UpsertPhotoHash :exec
INSERT INTO photo_hashes (device_serial, rel_path, dhash, content_hash)
VALUES (?, ?, ?, ?)
ON CONFLICT (device_serial, rel_path)
DO UPDATE SET
    dhash        = excluded.dhash,
    content_hash = excluded.content_hash,
    computed_at  = datetime('now');

-- name: ListExactDuplicates :many
SELECT content_hash, device_serial, rel_path
FROM photo_hashes
WHERE content_hash IS NOT NULL
  AND content_hash IN (
      SELECT content_hash FROM photo_hashes
      WHERE content_hash IS NOT NULL
      GROUP BY content_hash HAVING COUNT(*) > 1
  )
ORDER BY content_hash, device_serial, rel_path;

-- name: ListNearDuplicates :many
SELECT dhash, content_hash, device_serial, rel_path
FROM photo_hashes
WHERE dhash IS NOT NULL
ORDER BY dhash, device_serial, rel_path;

-- DeletePhotoHash drops the hashes of one photo that is no longer on disk.
-- name: DeletePhotoHash :exec
DELETE FROM photo_hashes
WHERE device_serial = ? AND rel_path = ?;

-- DeletePhotoHashesUnder drops the hashes of a deleted or moved path, and of
-- everything under it when the path is a folder.
-- name: DeletePhotoHashesUnder :exec
DELETE FROM photo_hashes
WHERE
    device_serial = sqlc.arg(device_serial)
    AND (
        rel_path = sqlc.arg(rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(rel_path)) + 1) = sqlc.arg(rel_path) || '/'
    );
