-- Back to one shared set of favorites and albums, keeping the oldest admin's.
-- Everyone else's albums are deleted, and their favorites fold into one list.
--
-- photo_albums.user_id stays: SQLite cannot DROP COLUMN a column carrying a
-- foreign key, and rebuilding the table would cascade-delete
-- photo_album_items. Nothing before 013 reads it.
DELETE FROM photo_albums
WHERE
    user_id IS NULL
    OR user_id IS NOT (
        SELECT
            id
        FROM
            users
        WHERE
            is_admin = 1
        ORDER BY
            created_at,
            id
        LIMIT
            1
    );

DROP INDEX IF EXISTS idx_photo_albums_smart_type;

CREATE UNIQUE INDEX idx_photo_albums_smart_type ON photo_albums (smart_type)
WHERE
    smart_type IS NOT NULL;

DROP INDEX IF EXISTS idx_photo_albums_sibling_name;

CREATE UNIQUE INDEX idx_photo_albums_sibling_name ON photo_albums (IFNULL(parent_id, 0), name COLLATE NOCASE);

CREATE TABLE photo_favorites_old (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_serial TEXT NOT NULL DEFAULT '',
    rel_path TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT (datetime('now')),
    UNIQUE (device_serial, rel_path)
);

-- Two accounts starring the same photo become one favorite.
INSERT OR IGNORE INTO
    photo_favorites_old (id, device_serial, rel_path, created_at)
SELECT
    id,
    device_serial,
    rel_path,
    created_at
FROM
    photo_favorites
ORDER BY
    id;

DROP TABLE photo_favorites;

ALTER TABLE photo_favorites_old
RENAME TO photo_favorites;
