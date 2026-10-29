-- Content search on PostgreSQL (#2958). SQLite's is the FTS5 table
-- file_content_fts from 006_file_search; this is its counterpart, a tsvector
-- of the extracted text with a GIN index over it.
--
-- 'english' is the nearest PostgreSQL has to FTS5's 'porter unicode61': it
-- stems the same way, so "run" finds "running". Unlike FTS5 it drops English
-- stop words and keeps diacritics; docs/architecture/data.md lists what
-- that changes. db.SearchContent is the one reader.
--
-- The column is generated, so the shared UpsertFileContent keeps it current
-- the way 006's triggers keep the FTS5 index current. It is the one column
-- the SQLite schema does not have, which TestPostgresSchemaMatchesSQLite
-- names, and sqlc's models carry it only in pgdb, where no query reads it.
ALTER TABLE file_content
    ADD COLUMN search_vector TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', extracted)) STORED;

CREATE INDEX idx_file_content_search_vector ON file_content USING GIN (search_vector);
