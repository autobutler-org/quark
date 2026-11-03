-- Column defaults stamp milliseconds (#3170). SQLite's datetime('now') has
-- one-second resolution, so rows written within the same second tied where
-- PostgreSQL's CURRENT_TIMESTAMP orders them. strftime with %f is the finest
-- SQLite's date functions offer: 'YYYY-MM-DD HH:MM:SS.SSS', which sorts
-- after an older second-precision value of the same second, so existing rows
-- need no rewrite.
--
-- SQLite cannot ALTER a column's default, and rebuilding every table that
-- carries one would mean copying each table, its indexes and its triggers.
-- A default does not touch the stored rows, so this edits the CREATE TABLE
-- text in sqlite_master directly, the procedure SQLite documents for changing
-- a default (https://www.sqlite.org/lang_altertable.html#otheralter). The
-- CREATE and DROP at the end bump the schema cookie, which makes every other
-- open connection reload the schema; writable_schema=RESET reloads this one.
PRAGMA writable_schema = ON;

UPDATE sqlite_master
SET sql = replace(sql, 'DEFAULT (datetime(''now''))', 'DEFAULT (strftime(''%Y-%m-%d %H:%M:%f'', ''now''))')
WHERE type = 'table' AND instr(sql, 'DEFAULT (datetime(''now''))') > 0;

PRAGMA writable_schema = OFF;

CREATE TABLE schema_cookie_bump_044 (id INTEGER);
DROP TABLE schema_cookie_bump_044;

PRAGMA writable_schema = RESET;
