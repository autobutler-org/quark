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

-- ListJobs for one account, so a non-admin's listing never loads every other
-- account's jobs (#2756).
-- name: ListUserJobs :many
SELECT
    *
FROM
    jobs
WHERE
    user_id = sqlc.arg(user_id)
    AND kind IN (sqlc.slice('kinds'))
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

-- Claims a pending job for an instance (#2966). The status guard makes a job
-- canceled or claimed by another instance since it was picked match no row,
-- and so does the lane count, which is what holds a lane's limit across
-- instances. The count is exact on SQLite, which has one writer at a time.
-- PostgreSQL at READ COMMITTED lets two claims count before either commits,
-- so that backend has to serialize claims per lane when it lands.
-- name: ClaimJob :one
UPDATE jobs
SET
    status = 'running',
    attempts = attempts + 1,
    started_at = datetime('now'),
    owner = sqlc.arg(owner),
    heartbeat_at = datetime('now')
WHERE
    jobs.id = sqlc.arg(id)
    AND jobs.status = 'pending'
    AND (
        SELECT
            COUNT(*)
        FROM
            jobs AS busy
        WHERE
            busy.status = 'running'
            AND busy.kind = jobs.kind
            AND busy.lane = jobs.lane
    ) < CAST(sqlc.arg(lane_limit) AS INTEGER)
RETURNING *;

-- The owner guard keeps an instance whose job was reclaimed from writing to a
-- run that is no longer its own.
-- name: UpdateJobProgress :execrows
UPDATE jobs
SET
    progress = ?
WHERE
    id = ?
    AND status = 'running'
    AND owner = ?;

-- Only a running job is finished here, so a job canceled while its handler
-- was still unwinding keeps the canceled status Cancel gave it, and only by
-- its owner, so a reclaimed job is settled by the instance that reran it.
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
    AND owner = ?
RETURNING *;

-- An instance's heartbeat: every job it is still running, which it compares
-- with what it has in memory to learn of one canceled or reclaimed elsewhere.
-- name: HeartbeatJobs :many
UPDATE jobs
SET
    heartbeat_at = datetime('now')
WHERE
    owner = ?
    AND status = 'running'
RETURNING id;

-- Puts a job its owner was running back in the queue, for an instance that
-- is shutting down: another one, or this one's next start, runs it again.
-- name: ReleaseJob :one
UPDATE jobs
SET
    status = 'pending',
    progress = 0,
    owner = '',
    heartbeat_at = NULL,
    started_at = NULL
WHERE
    id = ?
    AND status = 'running'
    AND owner = ?
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

-- A running job whose owner has not beaten for lease_seconds belongs to an
-- instance that is gone. The database's clock is on both sides of the
-- comparison, so instances need not agree on the time. One that has already
-- started max_attempts times fails here, so a job that kills its process does
-- not do it forever; run this before RequeueStaleJobs.
-- name: FailExhaustedStaleJobs :many
UPDATE jobs
SET
    status = 'failed',
    error = sqlc.arg(reason),
    finished_at = datetime('now')
WHERE
    status = 'running'
    AND attempts >= sqlc.arg(max_attempts)
    AND (
        heartbeat_at IS NULL
        OR heartbeat_at < datetime('now', '-' || CAST(sqlc.arg(lease_seconds) AS INTEGER) || ' seconds')
    )
RETURNING *;

-- Every other running job whose owner stopped beating goes back in the queue
-- for any instance to run.
-- name: RequeueStaleJobs :many
UPDATE jobs
SET
    status = 'pending',
    progress = 0,
    owner = '',
    heartbeat_at = NULL,
    started_at = NULL
WHERE
    status = 'running'
    AND (
        heartbeat_at IS NULL
        OR heartbeat_at < datetime('now', '-' || CAST(sqlc.arg(lease_seconds) AS INTEGER) || ' seconds')
    )
RETURNING *;

-- Drops finished jobs that finished before the cutoff, and every finished job
-- past each owner's newest keep, so job history is bounded per account
-- (#2756). Pending and running jobs are never touched.
-- name: PruneFinishedJobs :execrows
DELETE FROM jobs
WHERE
    jobs.status IN ('completed', 'failed', 'canceled')
    AND (
        jobs.finished_at < sqlc.arg(cutoff)
        OR jobs.id <= (
            SELECT
                newer.id
            FROM
                jobs AS newer
            WHERE
                newer.status IN ('completed', 'failed', 'canceled')
                AND newer.user_id IS jobs.user_id
            ORDER BY
                newer.id DESC
            LIMIT
                1
            OFFSET
                sqlc.arg(keep)
        )
    );

-- The backup holding a target device's lock (#3084): idx_jobs_backup_target
-- allows one pending or running snapshot backup per target.
-- name: GetActiveBackupJob :one
SELECT
    *
FROM
    jobs
WHERE
    kind = 'snapshot-backup'
    AND status IN ('pending', 'running')
    AND json_extract(params, '$.targetDeviceSerial') = CAST(sqlc.arg(target_device_serial) AS TEXT)
LIMIT
    1;

-- The status guard keeps a job finished or canceled since from being touched.
-- name: UpdateJobDetail :exec
UPDATE jobs
SET
    detail = ?
WHERE
    id = ?
    AND status = 'running';
