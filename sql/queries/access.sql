-- ListPathAccessForUser returns every row that applies to a user: their own,
-- their groups', and the built-in everyone group's. accessutil resolves
-- ancestors in memory from this one read.
-- name: ListPathAccessForUser :many
SELECT
    device_serial,
    rel_path,
    level
FROM
    path_access
WHERE
    path_access.user_id = sqlc.arg(user_id)
    OR path_access.group_id IN (
        SELECT
            group_id
        FROM
            group_members
        WHERE
            group_members.user_id = sqlc.arg(user_id)
    )
    OR path_access.group_id IN (
        SELECT
            id
        FROM
            groups
        WHERE
            name = 'everyone'
            AND builtin = 1
    );

-- SetUserPathAccess grants a user a level on a path, replacing the level any
-- earlier grant to that user on that path carried.
-- name: SetUserPathAccess :exec
INSERT INTO
    path_access (device_serial, rel_path, user_id, level)
VALUES
    (?, ?, ?, ?) ON CONFLICT (user_id, device_serial, rel_path)
WHERE
    user_id IS NOT NULL DO
UPDATE
SET
    level = excluded.level;

-- ReassignOwnerRows gives an heir every path one user owns, before that user
-- is deleted and ON DELETE CASCADE drops the rest of their rows (#1909). A
-- path the heir already has a row on becomes theirs to own. The WHERE clause
-- is load-bearing: without one, SQLite reads the ON of the upsert as a join
-- constraint of the SELECT. The CAST gives sqlc a type for the heir's id.
-- name: ReassignOwnerRows :execrows
INSERT INTO
    path_access (device_serial, rel_path, user_id, level)
SELECT
    device_serial,
    rel_path,
    CAST(sqlc.arg(to_user_id) AS INTEGER),
    'owner'
FROM
    path_access
WHERE
    path_access.user_id = sqlc.arg(from_user_id)
    AND level = 'owner' ON CONFLICT (user_id, device_serial, rel_path)
WHERE
    user_id IS NOT NULL DO
UPDATE
SET
    level = 'owner';

-- MovePathAccessTree points the rows on a path and everything beneath it at
-- where it moved, onto another device as well. substr, not LIKE: LIKE is
-- case-insensitive and treats _ and % as wildcards, and "foo" must not match
-- "foobar". The CAST gives sqlc a type for the parameter inside length().
-- name: MovePathAccessTree :execrows
UPDATE path_access
SET
    device_serial = sqlc.arg(new_device_serial),
    rel_path = sqlc.arg(new_rel_path) || substr(rel_path, length(CAST(sqlc.arg(old_rel_path) AS TEXT)) + 1)
WHERE
    device_serial = sqlc.arg(old_device_serial)
    AND (
        rel_path = sqlc.arg(old_rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(old_rel_path)) + 1) = sqlc.arg(old_rel_path) || '/'
    );

-- DeletePathAccessTree drops the rows on a path and everything beneath it.
-- name: DeletePathAccessTree :execrows
DELETE FROM path_access
WHERE
    device_serial = sqlc.arg(device_serial)
    AND (
        rel_path = sqlc.arg(rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(rel_path)) + 1) = sqlc.arg(rel_path) || '/'
    );
