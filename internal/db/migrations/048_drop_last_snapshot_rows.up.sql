-- The last snapshot time now comes from the backup runs themselves, through
-- each backup drive's backupRuns:<serial> row (#4044). These rows recorded
-- it apart from the runs, and drifted once a run could be deleted.
DELETE FROM settings
WHERE
    key = 'lastSnapshotBackup'
    OR key LIKE 'lastSnapshotBackup:%';
