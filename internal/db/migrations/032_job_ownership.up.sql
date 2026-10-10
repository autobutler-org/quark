-- Job ownership and single-run maintenance for several instances on one
-- database (#2966).

-- The instance running a job, and when it last said so. A running row whose
-- owner has stopped beating is reclaimed by whichever instance notices; one
-- that is still beating is left alone, however many instances start.
ALTER TABLE jobs
ADD COLUMN owner TEXT NOT NULL DEFAULT '';

ALTER TABLE jobs
ADD COLUMN heartbeat_at DATETIME;

-- One row per periodic maintenance task: who last ran it and when. An
-- instance runs a task only when it moves started_at forward, so a task runs
-- once per interval however many instances tick. This is the portable
-- stand-in for a PostgreSQL advisory lock, since sqlc's only engine here is
-- SQLite.
CREATE TABLE maintenance_runs (
    name TEXT PRIMARY KEY,
    owner TEXT NOT NULL,
    started_at DATETIME NOT NULL
);
