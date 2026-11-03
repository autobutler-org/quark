-- Reverses 044_millisecond_timestamps.up.sql: the defaults go back to
-- datetime('now'), by the same sqlite_master edit.
PRAGMA writable_schema = ON;

UPDATE sqlite_master
SET sql = replace(sql, 'DEFAULT (strftime(''%Y-%m-%d %H:%M:%f'', ''now''))', 'DEFAULT (datetime(''now''))')
WHERE type = 'table' AND instr(sql, 'DEFAULT (strftime(''%Y-%m-%d %H:%M:%f'', ''now''))') > 0;

PRAGMA writable_schema = OFF;

CREATE TABLE schema_cookie_bump_044 (id INTEGER);
DROP TABLE schema_cookie_bump_044;

PRAGMA writable_schema = RESET;
