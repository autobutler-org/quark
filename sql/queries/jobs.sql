-- name: CreateJob :one
INSERT INTO
    jobs (kind, name, params, lane, user_id)
VALUES
    (?, ?, ?, ?, ?)
RETURNING *;

-- name: GetJob :one
SELECT
    *
FROM
    jobs
WHERE
    id = ?
LIMIT
    1;

-- name: ListJobs :many
SELECT
    *
FROM
    jobs
WHERE
    kind IN (sqlc.slice('kinds'))
ORDER BY
    id DESC;

-- The pending jobs, oldest first, for the dispatcher to pick from by lane.
-- name: ListPendingJobs :many
SELECT
    id,
    kind,
    lane
FROM
    jobs
WHERE
    status = 'pending'
ORDER BY
    id;

-- The status guard makes a job canceled since it was picked match no row.
-- name: ClaimJob :one
UPDATE jobs
SET
    status = 'running',
    attempts = attempts + 1,
    started_at = datetime('now')
WHERE
    id = ?
    AND status = 'pending'
RETURNING *;

-- name: UpdateJobProgress :execrows
UPDATE jobs
SET
    progress = ?
WHERE
    id = ?
    AND status = 'running';

-- Only a running job is finished here, so a job canceled while its handler
-- was still unwinding keeps the canceled status Cancel gave it.
-- name: FinishJob :one
UPDATE jobs
SET
    status = ?,
    error = ?,
    progress = ?,
    finished_at = datetime('now')
WHERE
    id = ?
    AND status = 'running'
RETURNING *;

-- Resets a failed job so it runs again, in the lane its kind picked again.
-- The status guard makes a second, racing retry match no row. created_at is
-- left alone.
-- name: RetryJob :one
UPDATE jobs
SET
    status = 'pending',
    lane = ?,
    progress = 0,
    error = '',
    started_at = NULL,
    finished_at = NULL
WHERE
    id = ?
    AND status = 'failed'
RETURNING *;

-- name: CancelJob :one
UPDATE jobs
SET
    status = 'canceled',
    finished_at = datetime('now')
WHERE
    id = ?
    AND status IN ('pending', 'running')
RETURNING *;

-- Rows still running when a process starts belong to one that is gone.
-- name: InterruptRunningJobs :exec
UPDATE jobs
SET
    status = 'failed',
    error = sqlc.arg(reason),
    finished_at = datetime('now')
WHERE
    status = 'running';
