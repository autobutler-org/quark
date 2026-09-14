-- Album names become path segments (Trips/Japan), so a name cannot contain '/'
-- and must be unique among its siblings ignoring case. Root albums are siblings
-- of each other, and the system Favorites album is a root sibling like any
-- other.
--
-- This must not fail on a device with existing data: a failed migration leaves
-- the database dirty, and initSchema rebuilds a dirty database from scratch. So
-- existing names are repaired first and the index is created last.

-- 1. '/' is the path separator now. Replacing it can create new duplicates,
--    which step 2 then resolves.
UPDATE photo_albums
SET
    name = replace(name, '/', '-')
WHERE
    instr(name, '/') > 0;

-- 2. Pick the albums that lose their name. In each sibling group (same parent,
--    same name under NOCASE, the folding the index below uses) a system album
--    keeps its name, then the oldest user album (lowest id). A user album at the
--    root named Favorites loses too, even when the system album has not been
--    created yet, so it can never block EnsureFavoritesAlbum.
CREATE TEMP TABLE album_name_losers AS
SELECT
    r.id,
    r.parent_id,
    r.name
FROM
    photo_albums r
WHERE
    r.smart_type IS NULL
    AND (
        (r.parent_id IS NULL AND r.name COLLATE NOCASE = 'Favorites')
        OR EXISTS (
            SELECT
                1
            FROM
                photo_albums s
            WHERE
                IFNULL(s.parent_id, 0) = IFNULL(r.parent_id, 0)
                AND s.name COLLATE NOCASE = r.name
                AND s.id <> r.id
                AND (s.smart_type IS NOT NULL OR s.id < r.id)
        )
    );

-- 3. Rename each loser to "<name> (<id>)", or "<name> (<id>.<n>)" when a
--    sibling already holds that exact name. This is guaranteed collision-free:
--    - Two losers never pick the same name: each name ends in its own row id.
--    - A loser never picks a sibling's name: every candidate is checked against
--      all current names at that parent. Candidates for one loser differ from
--      each other in their digits, so no sibling name matches two of them, and
--      n runs from 0 to the album count, which is more candidates than the
--      loser has siblings. At least one is always free.
CREATE TEMP TABLE album_name_counter (n INTEGER PRIMARY KEY);

WITH RECURSIVE
    counter (n) AS (
        SELECT
            0
        UNION ALL
        SELECT
            n + 1
        FROM
            counter
        WHERE
            n < (
                SELECT
                    COUNT(*)
                FROM
                    photo_albums
            )
    )
INSERT INTO
    album_name_counter (n)
SELECT
    n
FROM
    counter;

UPDATE photo_albums
SET
    name = (
        SELECT
            l.name || ' (' || l.id || CASE WHEN c.n = 0 THEN '' ELSE '.' || c.n END || ')'
        FROM
            album_name_losers l,
            album_name_counter c
        WHERE
            l.id = photo_albums.id
            AND NOT EXISTS (
                SELECT
                    1
                FROM
                    photo_albums s
                WHERE
                    IFNULL(s.parent_id, 0) = IFNULL(l.parent_id, 0)
                    AND s.name COLLATE NOCASE = l.name || ' (' || l.id || CASE WHEN c.n = 0 THEN '' ELSE '.' || c.n END || ')'
            )
        ORDER BY
            c.n
        LIMIT
            1
    )
WHERE
    id IN (
        SELECT
            id
        FROM
            album_name_losers
    );

DROP TABLE album_name_counter;

DROP TABLE album_name_losers;

-- 4. Enforce it. SQLite treats NULLs as distinct in a unique index, so
--    parent_id alone would let two root albums share a name; IFNULL folds the
--    root into parent 0, which no album can be (AUTOINCREMENT starts at 1).
CREATE UNIQUE INDEX IF NOT EXISTS idx_photo_albums_sibling_name ON photo_albums (IFNULL(parent_id, 0), name COLLATE NOCASE);
