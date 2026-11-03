-- The filename index (#2956): one row per file and folder on every managed
-- device, which filename search, the photo, recent and by-type listings and
-- folder sizes read instead of a tree held in process memory. A row is keyed by
-- the device serial ('' for the internal drive), the folder it sits in (dir,
-- '' at the device's root) and its name; its path is dir/name.
--
-- search_name is strings.ToLower(name), lowered in Go, so a substring of it
-- matches exactly as the in-memory index did: SQLite's LOWER folds ASCII only.
-- Folders carry size 0, so a folder's total is the SUM over the rows under it.
-- indexed_at is when the row was last written, in Unix nanoseconds; a
-- reconcile deletes the rows it did not write. pkg/util/indexutil is the one
-- writer and reader.
CREATE TABLE file_index (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    serial      TEXT    NOT NULL,
    dir         TEXT    NOT NULL,
    name        TEXT    NOT NULL,
    search_name TEXT    NOT NULL,
    is_dir      BOOLEAN NOT NULL,
    size        INTEGER NOT NULL,
    mod_time    INTEGER NOT NULL,
    indexed_at  INTEGER NOT NULL,
    UNIQUE (serial, dir, name)
);

-- A trigram index over search_name answers a substring query of three or
-- more characters without reading every name (db.SearchIndexedFiles). It is
-- case-sensitive because search_name is already lowered, so it matches
-- exactly what strings.Contains does on the lowered name. External content,
-- like file_content_fts: it stores the trigrams, not the names.
CREATE VIRTUAL TABLE file_index_fts USING fts5(
    search_name,
    content=file_index,
    content_rowid=id,
    tokenize='trigram case_sensitive 1'
);

CREATE TRIGGER file_index_ai
AFTER INSERT ON file_index BEGIN
    INSERT INTO file_index_fts(rowid, search_name) VALUES (new.id, new.search_name);
END;

CREATE TRIGGER file_index_ad
AFTER DELETE ON file_index BEGIN
    INSERT INTO file_index_fts(file_index_fts, rowid, search_name) VALUES ('delete', old.id, old.search_name);
END;

-- Only a rename changes search_name. A reconcile's upsert, or a folder move
-- rewriting dir under it, leaves it alone and costs the FTS index nothing.
CREATE TRIGGER file_index_au
AFTER UPDATE OF search_name ON file_index BEGIN
    INSERT INTO file_index_fts(file_index_fts, rowid, search_name) VALUES ('delete', old.id, old.search_name);
    INSERT INTO file_index_fts(rowid, search_name) VALUES (new.id, new.search_name);
END;
