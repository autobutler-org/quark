-- Favorites and albums belong to one account (#1912). Deleting the account
-- deletes them; the photos themselves stay on disk.
--
-- This must not fail on a device with existing data: a failed migration leaves
-- the database dirty, and initSchema rebuilds a dirty database from scratch.
-- Existing rows go to the oldest admin, the account that set the device up.
-- With no admin there is nobody to give them to, so they are deleted.
--
-- Migrations run in a transaction with foreign keys on, so photo_albums gains
-- its column in place: rebuilding it would cascade-delete photo_album_items.
-- SQLite only lets ADD COLUMN add a foreign key whose default is NULL, so the
-- column stays nullable and the app always writes it.
ALTER TABLE photo_albums
ADD COLUMN user_id INTEGER REFERENCES users (id) ON DELETE CASCADE;

UPDATE photo_albums
SET
    user_id = (
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

-- Only when there is no admin. Children and items go with their album.
DELETE FROM photo_albums
WHERE
    user_id IS NULL;

-- Each account has its own Favorites album, and its own root to name albums in.
-- One owner holds every existing row, so the old global uniqueness carries over.
DROP INDEX IF EXISTS idx_photo_albums_smart_type;

CREATE UNIQUE INDEX idx_photo_albums_smart_type ON photo_albums (user_id, smart_type)
WHERE
    smart_type IS NOT NULL;

DROP INDEX IF EXISTS idx_photo_albums_sibling_name;

CREATE UNIQUE INDEX idx_photo_albums_sibling_name ON photo_albums (user_id, IFNULL(parent_id, 0), name COLLATE NOCASE);

-- Nothing references photo_favorites, so it can be rebuilt with a NOT NULL
-- owner. The cross join with the oldest admin copies nothing when there is none.
CREATE TABLE photo_favorites_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    device_serial TEXT NOT NULL DEFAULT '',
    rel_path TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    UNIQUE (user_id, device_serial, rel_path)
);

INSERT INTO
    photo_favorites_new (id, user_id, device_serial, rel_path, created_at)
SELECT
    f.id,
    founder.id,
    f.device_serial,
    f.rel_path,
    f.created_at
FROM
    photo_favorites f,
    (
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
    ) founder;

DROP TABLE photo_favorites;

ALTER TABLE photo_favorites_new
RENAME TO photo_favorites;
