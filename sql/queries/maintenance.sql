-- Makes sure a periodic task has a row for ClaimMaintenanceRun to take, dated
-- so that a task that has never run is due.
-- name: EnsureMaintenanceRun :exec
INSERT INTO
    maintenance_runs (name, owner, started_at)
VALUES
    (?, '', datetime('now', '-100 years'))
ON CONFLICT (name) DO NOTHING;

-- Takes a periodic task's turn (#2966): the row is written only when the task
-- last started at least interval_seconds ago, so of the instances ticking on
-- one database exactly one changes a row per interval. The database's clock
-- is on both sides of the comparison, so instances need not agree on the
-- time.
-- name: ClaimMaintenanceRun :execrows
UPDATE maintenance_runs
SET
    owner = sqlc.arg(owner),
    started_at = datetime('now')
WHERE
    name = sqlc.arg(name)
    AND started_at <= datetime('now', '-' || CAST(sqlc.arg(interval_seconds) AS INTEGER) || ' seconds');
