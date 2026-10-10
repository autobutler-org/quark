DROP INDEX IF EXISTS idx_jobs_backup_target;

ALTER TABLE jobs
DROP COLUMN detail;
