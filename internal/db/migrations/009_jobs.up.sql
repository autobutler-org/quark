-- Background jobs (#1122). One row per job: retrying a failed job resets its
-- row to pending rather than inserting another. params is the kind-specific
-- JSON its handler reads each time the job runs.
CREATE TABLE
    IF NOT EXISTS jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending' CHECK (
            status IN ('pending', 'running', 'completed', 'failed', 'canceled')
        ),
        params TEXT NOT NULL DEFAULT '{}',
        progress REAL NOT NULL DEFAULT 0,
        -- The concurrency lane within the kind the job runs in. Each kind caps
        -- how many of its jobs run at once per lane, so a quick stream copy is
        -- not held behind a long re-encode.
        lane TEXT NOT NULL DEFAULT '',
        -- How many times the job has started running. Claiming bumps it; a
        -- retry leaves it alone until the job runs again.
        attempts INTEGER NOT NULL DEFAULT 0,
        error TEXT NOT NULL DEFAULT '',
        created_at DATETIME NOT NULL DEFAULT (datetime('now')),
        started_at DATETIME,
        finished_at DATETIME
    );

-- Serves the dispatcher's scan of pending jobs, oldest first. Listing newest
-- first walks the primary key and needs nothing extra.
CREATE INDEX IF NOT EXISTS idx_jobs_status_id ON jobs (status, id);
