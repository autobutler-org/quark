-- The filename index (044_file_index), written and read by pkg/util/indexutil.
--
-- A path is (dir, name). The subtree under a folder at path is every row whose
-- dir is path or starts with path/, which the queries take as dir = path or
-- dir in [dir_from, dir_to), with dir_from = path + '/' and dir_to = path + '0'
-- ('0' is the byte after '/'), so the (serial, dir, name) index serves it as a
-- range on both engines.

-- name: UpsertIndexedEntry :exec
INSERT INTO file_index (serial, dir, name, search_name, is_dir, size, mod_time, indexed_at)
VALUES (
    sqlc.arg(serial), sqlc.arg(dir), sqlc.arg(name), sqlc.arg(search_name),
    sqlc.arg(is_dir), sqlc.arg(size), sqlc.arg(mod_time), sqlc.arg(indexed_at)
)
ON CONFLICT (serial, dir, name) DO UPDATE SET
    is_dir     = excluded.is_dir,
    size       = excluded.size,
    mod_time   = excluded.mod_time,
    indexed_at = excluded.indexed_at;

-- DeleteIndexedPath drops the entry at (parent, name) and, when it is a
-- folder at path, everything under it, in one statement (#2754).
-- name: DeleteIndexedPath :execrows
DELETE FROM file_index
WHERE serial = sqlc.arg(serial)
  AND ((dir = sqlc.arg(parent) AND name = sqlc.arg(name))
       OR dir = sqlc.arg(path)
       OR (dir >= sqlc.arg(dir_from) AND dir < sqlc.arg(dir_to)));

-- DeleteIndexedDescendants drops everything under the folder at path, but not
-- the entry for path itself.
-- name: DeleteIndexedDescendants :exec
DELETE FROM file_index
WHERE serial = sqlc.arg(serial)
  AND (dir = sqlc.arg(path) OR (dir >= sqlc.arg(dir_from) AND dir < sqlc.arg(dir_to)));

-- MoveIndexedDescendants rewrites the dir of everything under the folder at
-- path to sit under new_path instead. LENGTH and SUBSTR count characters on
-- both engines.
-- name: MoveIndexedDescendants :execrows
UPDATE file_index
SET dir = sqlc.arg(new_path) || SUBSTR(dir, LENGTH(CAST(sqlc.arg(path) AS TEXT)) + 1)
WHERE serial = sqlc.arg(serial)
  AND (dir = sqlc.arg(path) OR (dir >= sqlc.arg(dir_from) AND dir < sqlc.arg(dir_to)));

-- name: RenameIndexedEntry :execrows
UPDATE file_index
SET dir = sqlc.arg(new_dir), name = sqlc.arg(new_name), search_name = sqlc.arg(new_search_name)
WHERE serial = sqlc.arg(serial) AND dir = sqlc.arg(dir) AND name = sqlc.arg(name);

-- name: ListIndexedSerials :many
SELECT DISTINCT serial FROM file_index ORDER BY serial;

-- name: DeleteIndexedSerial :exec
DELETE FROM file_index WHERE serial = sqlc.arg(serial);

-- DeleteStaleIndexedSerial drops what a reconcile of the device did not write.
-- name: DeleteStaleIndexedSerial :exec
DELETE FROM file_index WHERE serial = sqlc.arg(serial) AND indexed_at < sqlc.arg(indexed_at);

-- ListStaleIndexedChildren names what directly in dir a rescan did not write.
-- name: ListStaleIndexedChildren :many
SELECT name FROM file_index
WHERE serial = sqlc.arg(serial) AND dir = sqlc.arg(dir) AND indexed_at < sqlc.arg(indexed_at);

-- name: ListIndexedChildFolders :many
SELECT name FROM file_index
WHERE serial = sqlc.arg(serial) AND dir = sqlc.arg(dir) AND is_dir = TRUE;

-- name: SumIndexedSerial :one
SELECT CAST(COALESCE(SUM(size), 0) AS BIGINT) AS total, COUNT(*) AS entries
FROM file_index WHERE serial = sqlc.arg(serial);

-- SumIndexedFolder totals the folder at path. entries counts its own row
-- with what is under it, so zero means the index holds no such folder.
-- name: SumIndexedFolder :one
SELECT CAST(COALESCE(SUM(size), 0) AS BIGINT) AS total, COUNT(*) AS entries
FROM file_index
WHERE serial = sqlc.arg(serial)
  AND ((dir = sqlc.arg(parent) AND name = sqlc.arg(name) AND is_dir = TRUE)
       OR dir = sqlc.arg(path)
       OR (dir >= sqlc.arg(dir_from) AND dir < sqlc.arg(dir_to)));

-- ListIndexedFilesPage returns the next page of files on a device whose
-- search_name holds query, in (dir, name) order after (after_dir,
-- after_name). The leading dir >= after_dir lets the index seek to the page
-- rather than read past every earlier row. db.SearchIndexedFiles is the
-- caller and query is already lowered; the empty query matches every file.
-- instr rather than LIKE, so % and _ in a query are only characters: sqlc's
-- SQLite parser takes no ESCAPE, and PostgreSQL's instr is defined in
-- 044_file_index.
-- name: ListIndexedFilesPage :many
SELECT dir, name, size, mod_time FROM file_index
WHERE serial = sqlc.arg(serial)
  AND is_dir = FALSE
  AND instr(search_name, sqlc.arg(query)) > 0
  AND dir >= sqlc.arg(after_dir)
  AND (dir > sqlc.arg(after_dir) OR name > sqlc.arg(after_name))
ORDER BY dir, name
LIMIT CAST(sqlc.arg('limit') AS BIGINT);
