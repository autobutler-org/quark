-- Music library cache (#2982). Every column is derived from an audio file, so
-- dropping the table loses nothing a rescan cannot rebuild. serial is '' for
-- the internal drive. size and mtime (unix seconds) plus scanner_version are
-- the unchanged-file check: a backfill does not open a file whose row still
-- matches. album_key is a hex hash of lower(album_artist), lower(album) and
-- the parent folder, so two "Greatest Hits" albums by one artist stay apart.
-- duration_exact is 0 when duration_ms is a bitrate estimate. cover_source is
-- 'embedded', 'folder:<name>', or ''. cover_key is the hex sha256 of the
-- picture bytes, shared by every track that uses that picture.

CREATE TABLE music_tracks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    serial          TEXT    NOT NULL,
    rel_path        TEXT    NOT NULL,
    size            INTEGER NOT NULL,
    mtime           INTEGER NOT NULL,
    scanner_version INTEGER NOT NULL,
    title           TEXT    NOT NULL DEFAULT '',
    artist          TEXT    NOT NULL DEFAULT '',
    album_artist    TEXT    NOT NULL DEFAULT '',
    album           TEXT    NOT NULL DEFAULT '',
    album_key       TEXT    NOT NULL DEFAULT '',
    genre           TEXT    NOT NULL DEFAULT '',
    track_no        INTEGER,
    disc_no         INTEGER,
    year            INTEGER,
    duration_ms     INTEGER,
    duration_exact  INTEGER NOT NULL DEFAULT 1,
    cover_source    TEXT    NOT NULL DEFAULT '',
    cover_key       TEXT    NOT NULL DEFAULT '',
    UNIQUE (serial, rel_path)
);

CREATE INDEX idx_music_tracks_album ON music_tracks (album_key);

CREATE INDEX idx_music_tracks_artist ON music_tracks (LOWER(album_artist));

CREATE INDEX idx_music_tracks_genre ON music_tracks (LOWER(genre));

-- FTS5 external content, SQLite only. PostgreSQL has no music_tracks_fts;
-- music search follows content search onto that engine (#2958). No porter
-- stemmer: stemming names helps nobody. remove_diacritics 2 folds accents in
-- the index and in the query.
CREATE VIRTUAL TABLE music_tracks_fts USING fts5(
    title, artist, album_artist, album, genre,
    content=music_tracks, content_rowid=id,
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TRIGGER music_tracks_ai
AFTER INSERT ON music_tracks BEGIN
    INSERT INTO music_tracks_fts(rowid, title, artist, album_artist, album, genre)
    VALUES (new.id, new.title, new.artist, new.album_artist, new.album, new.genre);
END;

CREATE TRIGGER music_tracks_ad
AFTER DELETE ON music_tracks BEGIN
    INSERT INTO music_tracks_fts(music_tracks_fts, rowid, title, artist, album_artist, album, genre)
    VALUES ('delete', old.id, old.title, old.artist, old.album_artist, old.album, old.genre);
END;

CREATE TRIGGER music_tracks_au
AFTER UPDATE ON music_tracks BEGIN
    INSERT INTO music_tracks_fts(music_tracks_fts, rowid, title, artist, album_artist, album, genre)
    VALUES ('delete', old.id, old.title, old.artist, old.album_artist, old.album, old.genre);
    INSERT INTO music_tracks_fts(rowid, title, artist, album_artist, album, genre)
    VALUES (new.id, new.title, new.artist, new.album_artist, new.album, new.genre);
END;
