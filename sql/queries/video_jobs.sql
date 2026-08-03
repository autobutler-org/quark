-- name: CreateVideoJob :one
INSERT INTO video_jobs (job_type, device_serial, input_rel_path, output_rel_path, params)
VALUES (?, ?, ?, ?, ?)
RETURNING id;

-- name: GetVideoJob :one
SELECT * FROM video_jobs WHERE id = ? LIMIT 1;

-- name: UpdateVideoJobStatus :exec
UPDATE video_jobs
SET status        = ?,
    progress      = ?,
    output_rel_path = ?,
    error_message = ?,
    updated_at    = datetime('now')
WHERE id = ?;

-- name: ListPendingVideoJobs :many
SELECT * FROM video_jobs
WHERE status = 'pending'
ORDER BY created_at ASC
LIMIT 10;

-- name: ListVideoJobs :many
SELECT * FROM video_jobs
ORDER BY created_at DESC
LIMIT 50;

-- name: CancelVideoJob :exec
UPDATE video_jobs
SET status     = 'cancelled',
    updated_at = datetime('now')
WHERE id = ? AND status = 'pending';
