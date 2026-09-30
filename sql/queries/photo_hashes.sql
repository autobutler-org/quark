-- UpsertPhotoHash stores a photo's hashes, and its capture date when
-- taken_checked says the EXIF was read. A write that did not read it keeps
-- the date already stored.
-- name: UpsertPhotoHash :exec
INSERT INTO photo_hashes (device_serial, rel_path, dhash, content_hash, taken_at, taken_checked)
VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT (device_serial, rel_path)
DO UPDATE SET
    dhash         = excluded.dhash,
    content_hash  = excluded.content_hash,
    taken_at      = CASE WHEN excluded.taken_checked THEN excluded.taken_at ELSE photo_hashes.taken_at END,
    taken_checked = photo_hashes.taken_checked OR excluded.taken_checked,
    computed_at   = datetime('now');

-- SetPhotoTakenAt records the capture date of a photo whose hashes are
-- already stored (#2592).
-- name: SetPhotoTakenAt :exec
UPDATE photo_hashes
SET taken_at = ?, taken_checked = 1
WHERE device_serial = ? AND rel_path = ?;

-- ListPhotoHashStates reports what is stored for every photo, for the
-- backfill to find what is missing.
-- name: ListPhotoHashStates :many
SELECT device_serial, rel_path, dhash, content_hash IS NOT NULL AS has_content_hash, taken_checked
FROM photo_hashes;

-- ListPhotoTakenAt returns every capture date known, for the date-taken sort.
-- name: ListPhotoTakenAt :many
SELECT device_serial, rel_path, taken_at
FROM photo_hashes
WHERE taken_at IS NOT NULL;

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
