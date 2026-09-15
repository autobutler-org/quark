-- SQLite cannot DROP COLUMN a column carrying a foreign key, and nothing
-- references jobs, so the table is rebuilt as 009 made it, keeping every row.
CREATE TABLE jobs_old (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (
        status IN ('pending', 'running', 'completed', 'failed', 'canceled')
    ),
    params TEXT NOT NULL DEFAULT '{}',
    progress REAL NOT NULL DEFAULT 0,
    lane TEXT NOT NULL DEFAULT '',
    attempts INTEGER NOT NULL DEFAULT 0,
    error TEXT NOT NULL DEFAULT '',
    created_at DATETIME NOT NULL DEFAULT (datetime('now')),
    started_at DATETIME,
    finished_at DATETIME
);

INSERT INTO
    jobs_old (
        id,
        kind,
        name,
        status,
        params,
        progress,
        lane,
        attempts,
        error,
        created_at,
        started_at,
        finished_at
    )
SELECT
    id,
    kind,
    name,
    status,
    params,
    progress,
    lane,
    attempts,
    error,
    created_at,
    started_at,
    finished_at
FROM
    jobs;

DROP TABLE jobs;

ALTER TABLE jobs_old
RENAME TO jobs;

CREATE INDEX IF NOT EXISTS idx_jobs_status_id ON jobs (status, id);
