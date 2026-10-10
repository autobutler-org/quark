-- Snapshot backups run on the job queue (#3084).

-- The per-target lock: at most one pending or running backup per target
-- device, whichever instance asks. A second start fails on this index instead
-- of on a check another instance could race.
CREATE UNIQUE INDEX idx_jobs_backup_target ON jobs (json_extract(params, '$.targetDeviceSerial'))
WHERE
    kind = 'snapshot-backup'
    AND status IN ('pending', 'running');

-- Kind-specific progress a handler saves while its job runs. A backup keeps
-- its phase and its file and byte counts here, so the instance answering a
-- status request need not be the one running the job.
ALTER TABLE jobs
ADD COLUMN detail TEXT NOT NULL DEFAULT '{}';
