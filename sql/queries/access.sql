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
