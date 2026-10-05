-- name: UpsertConnectedDevice :one
INSERT INTO
    connected_devices (ip_address, user_agent, first_seen_at, last_seen_at, request_count)
VALUES
    (?, ?, datetime('now'), datetime('now'), 1)
ON CONFLICT (ip_address, user_agent) DO UPDATE SET
    last_seen_at = datetime('now'),
    request_count = request_count + 1
RETURNING *;

-- name: ListConnectedDevices :many
SELECT
    *
FROM
    connected_devices
ORDER BY
    last_seen_at DESC;

-- name: GetConnectedDevice :one
SELECT
    *
FROM
    connected_devices
WHERE
    id = ?
LIMIT
    1;

-- name: DeleteConnectedDevice :exec
DELETE FROM connected_devices
WHERE
    id = ?;

-- name: CountConnectedDevices :one
SELECT
    COUNT(*)
FROM
    connected_devices;

-- Drops peers not seen since the cutoff, and every peer past the newest keep
-- by last_seen_at, so the table holds at most keep rows (#2756).
-- name: PruneConnectedDevices :execrows
DELETE FROM connected_devices
WHERE
    connected_devices.last_seen_at < sqlc.arg(cutoff)
    OR connected_devices.id NOT IN (
        SELECT
            newest.id
        FROM
            connected_devices AS newest
        ORDER BY
            newest.last_seen_at DESC,
            newest.id DESC
        LIMIT
            sqlc.arg(keep)
    );
