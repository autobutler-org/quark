-- Video processing job queue.
--
-- Supports long-running operations (transcode, future: batch export) that
-- cannot complete within a single HTTP request-response cycle.
CREATE TABLE IF NOT EXISTS video_jobs (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    job_type         TEXT    NOT NULL,                         -- 'transcode'
    status           TEXT    NOT NULL DEFAULT 'pending',       -- pending | running | completed | failed | cancelled
    device_serial    TEXT    NOT NULL DEFAULT '',
    input_rel_path   TEXT    NOT NULL,
    output_rel_path  TEXT    NOT NULL DEFAULT '',
    params           TEXT    NOT NULL DEFAULT '{}',            -- JSON: preset, options
    progress         REAL    NOT NULL DEFAULT 0,               -- 0.0 – 1.0
    error_message    TEXT    NOT NULL DEFAULT '',
    created_at       DATETIME NOT NULL DEFAULT (datetime('now')),
    updated_at       DATETIME NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_video_jobs_status ON video_jobs (status);
CREATE INDEX IF NOT EXISTS idx_video_jobs_created_at ON video_jobs (created_at);
