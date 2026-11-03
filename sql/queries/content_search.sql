-- name: UpsertFileContent :exec
INSERT INTO file_content (serial, rel_path, extracted, updated_at)
VALUES (sqlc.arg(serial), sqlc.arg(rel_path), sqlc.arg(extracted), strftime('%Y-%m-%d %H:%M:%f', 'now'))
ON CONFLICT(serial, rel_path) DO UPDATE SET
    extracted  = excluded.extracted,
    updated_at = excluded.updated_at;

-- name: DeleteFileContent :exec
DELETE FROM file_content WHERE serial = sqlc.arg(serial) AND rel_path = sqlc.arg(rel_path);

-- name: DeleteFileContentBySerial :exec
DELETE FROM file_content WHERE serial = sqlc.arg(serial);
