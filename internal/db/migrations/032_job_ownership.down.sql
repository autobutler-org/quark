DROP TABLE IF EXISTS maintenance_runs;

ALTER TABLE jobs
DROP COLUMN heartbeat_at;

ALTER TABLE jobs
DROP COLUMN owner;
