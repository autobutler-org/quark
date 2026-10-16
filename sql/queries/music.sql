-- Music library cache (#2982). pkg/util/musicutil is the caller. Search is
-- FTS5 (SQLite only, #2958) and is raw SQL there, not a query here.
--
-- A path and the files under it are matched with substr rather than LIKE, so
-- a '%' or '_' in a name is not a wildcard. The same shape as DeleteFavoritesUnder.

-- UpsertMusicTrack inserts a track or replaces the row already stored for
-- that file. The id is stable across a replacement.
-- name: UpsertMusicTrack :one
INSERT INTO music_tracks (
    serial, rel_path, size, mtime, scanner_version,
    title, artist, album_artist, album, album_key, genre,
    track_no, disc_no, year, duration_ms, duration_exact,
    cover_source, cover_key
) VALUES (
    sqlc.arg(serial), sqlc.arg(rel_path), sqlc.arg(size), sqlc.arg(mtime), sqlc.arg(scanner_version),
    sqlc.arg(title), sqlc.arg(artist), sqlc.arg(album_artist), sqlc.arg(album), sqlc.arg(album_key), sqlc.arg(genre),
    sqlc.arg(track_no), sqlc.arg(disc_no), sqlc.arg(year), sqlc.arg(duration_ms), sqlc.arg(duration_exact),
    sqlc.arg(cover_source), sqlc.arg(cover_key)
)
ON CONFLICT (serial, rel_path) DO UPDATE SET
    size            = excluded.size,
    mtime           = excluded.mtime,
    scanner_version = excluded.scanner_version,
    title           = excluded.title,
    artist          = excluded.artist,
    album_artist    = excluded.album_artist,
    album           = excluded.album,
    album_key       = excluded.album_key,
    genre           = excluded.genre,
    track_no        = excluded.track_no,
    disc_no         = excluded.disc_no,
    year            = excluded.year,
    duration_ms     = excluded.duration_ms,
    duration_exact  = excluded.duration_exact,
    cover_source    = excluded.cover_source,
    cover_key       = excluded.cover_key
RETURNING *;

-- DeleteMusicTracksUnder drops the track at rel_path, and every track under
-- it when rel_path is a folder.
-- name: DeleteMusicTracksUnder :exec
DELETE FROM music_tracks
WHERE
    serial = sqlc.arg(serial)
    AND (
        rel_path = sqlc.arg(rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(rel_path)) + 1) = sqlc.arg(rel_path) || '/'
    );

-- MoveMusicTracks rewrites rel_path for old_rel_path and everything under it.
-- album_key embeds the folder and is not recomputed here: the hash is built
-- in Go, and a move does not re-read the file. The library service updates
-- the key. A destination that is already a track fails the statement on the
-- unique (serial, rel_path); nothing is rewritten.
-- name: MoveMusicTracks :exec
UPDATE music_tracks
SET
    rel_path = CAST(sqlc.arg(new_rel_path) AS TEXT) || substr(music_tracks.rel_path, length(CAST(sqlc.arg(old_rel_path) AS TEXT)) + 1)
WHERE
    music_tracks.serial = sqlc.arg(serial)
    AND (
        music_tracks.rel_path = CAST(sqlc.arg(old_rel_path) AS TEXT)
        OR substr(music_tracks.rel_path, 1, length(sqlc.arg(old_rel_path)) + 1) = sqlc.arg(old_rel_path) || '/'
    );

-- DeleteMusicTracksBySerial drops a device's tracks when the drive goes away.
-- serial '' is the internal drive.
-- name: DeleteMusicTracksBySerial :exec
DELETE FROM music_tracks
WHERE serial = sqlc.arg(serial);

-- The unchanged-file check. A backfill skips a file whose size, mtime and
-- scanner_version still match, and deletes rows the walk did not see. Get is
-- one path; List is every path on a device, which is one read for a pass.
-- name: GetMusicTrackScanState :one
SELECT size, mtime, scanner_version
FROM music_tracks
WHERE serial = sqlc.arg(serial) AND rel_path = sqlc.arg(rel_path);

-- name: ListMusicTrackScanStates :many
SELECT rel_path, size, mtime, scanner_version
FROM music_tracks
WHERE serial = sqlc.arg(serial)
ORDER BY rel_path;

-- Browse aggregates. An admin's page is one of these queries. A caller who
-- cannot read the whole tree aggregates in Go from ListMusicTracksAfter
-- instead.
--
-- Displayed casing is MIN() of the stored tag, so "Rock" and "rock" are one
-- genre and the name does not flicker. SQLite's MIN is byte order;
-- PostgreSQL's follows the database collation. filter_artist is 0 or 1. 0 returns
-- every album; 1 keeps LOWER(album_artist) = LOWER(artist), and artist may
-- be empty.
--
-- The two cover subqueries share an ORDER BY over the unique (serial,
-- rel_path), so they name the same file: one with cover art if any track has
-- it, otherwise the first path.

-- name: ListMusicAlbums :many
SELECT
    album_key,
    CAST(MIN(album) AS TEXT) AS title,
    CAST(MIN(album_artist) AS TEXT) AS album_artist,
    -- A scalar subquery, not MIN(), so sqlc keeps year nullable. The smallest
    -- tagged year; no row when every track is untagged.
    (
        SELECT t.year
        FROM music_tracks AS t
        WHERE t.album_key = music_tracks.album_key AND t.year IS NOT NULL
        ORDER BY t.year
        LIMIT 1
    ) AS year,
    CAST(COUNT(*) AS BIGINT) AS track_count,
    CAST(COALESCE(SUM(duration_ms), 0) AS BIGINT) AS duration_ms,
    (
        SELECT t.serial
        FROM music_tracks AS t
        WHERE
            t.album_key = music_tracks.album_key
            AND (
                CAST(sqlc.arg(filter_artist) AS BIGINT) = 0
                OR LOWER(t.album_artist) = LOWER(CAST(sqlc.arg(artist) AS TEXT))
            )
        ORDER BY CASE WHEN t.cover_source != '' THEN 0 ELSE 1 END, t.rel_path, t.serial
        LIMIT 1
    ) AS cover_serial,
    (
        SELECT t.rel_path
        FROM music_tracks AS t
        WHERE
            t.album_key = music_tracks.album_key
            AND (
                CAST(sqlc.arg(filter_artist) AS BIGINT) = 0
                OR LOWER(t.album_artist) = LOWER(CAST(sqlc.arg(artist) AS TEXT))
            )
        ORDER BY CASE WHEN t.cover_source != '' THEN 0 ELSE 1 END, t.rel_path, t.serial
        LIMIT 1
    ) AS cover_path
FROM music_tracks
WHERE
    CAST(sqlc.arg(filter_artist) AS BIGINT) = 0
    OR LOWER(album_artist) = LOWER(CAST(sqlc.arg(artist) AS TEXT))
GROUP BY album_key
ORDER BY LOWER(MIN(album_artist)), LOWER(MIN(album)), album_key;

-- name: ListMusicArtists :many
SELECT
    CAST(grouped.name AS TEXT) AS name,
    grouped.album_count,
    grouped.track_count,
    (
        SELECT t.serial
        FROM music_tracks AS t
        WHERE LOWER(t.album_artist) = grouped.artist_key
        ORDER BY CASE WHEN t.cover_source != '' THEN 0 ELSE 1 END, t.rel_path, t.serial
        LIMIT 1
    ) AS cover_serial,
    (
        SELECT t.rel_path
        FROM music_tracks AS t
        WHERE LOWER(t.album_artist) = grouped.artist_key
        ORDER BY CASE WHEN t.cover_source != '' THEN 0 ELSE 1 END, t.rel_path, t.serial
        LIMIT 1
    ) AS cover_path
FROM (
    SELECT
        LOWER(album_artist) AS artist_key,
        MIN(album_artist) AS name,
        CAST(COUNT(DISTINCT album_key) AS BIGINT) AS album_count,
        CAST(COUNT(*) AS BIGINT) AS track_count
    FROM music_tracks
    GROUP BY LOWER(album_artist)
) AS grouped
ORDER BY grouped.artist_key;

-- name: ListMusicGenres :many
SELECT
    CAST(MIN(genre) AS TEXT) AS name,
    CAST(COUNT(*) AS BIGINT) AS track_count
FROM music_tracks
GROUP BY LOWER(genre)
ORDER BY LOWER(genre);

-- Track listing. filter_* are 0 or 1; with 0 the matching value is ignored.
-- sort is 'title', 'artist', 'album', 'year', 'added', or '' for album order;
-- descending is 0 or 1. The sort keys are computed in the select list because
-- sqlc's SQLite engine leaves a parameter in an ORDER BY CASE unexpanded. A key
-- the sort does not use is the same on every row and orders nothing. A numeric key
-- is negated for descending. Every sort ends on the album order and then id,
-- so a page boundary is stable, and nullable columns are COALESCEd so both
-- engines order them alike.
-- name: ListMusicTracks :many
SELECT
    sqlc.embed(music_tracks),
    CAST(
        COALESCE(CASE WHEN CAST(sqlc.arg(descending) AS BIGINT) = 0 THEN
            CASE CAST(sqlc.arg(sort) AS TEXT)
                WHEN 'title' THEN LOWER(music_tracks.title)
                WHEN 'artist' THEN LOWER(music_tracks.artist)
                WHEN 'album' THEN LOWER(music_tracks.album)
            END
        END, '') AS TEXT
    ) AS sort_text_asc,
    CAST(
        COALESCE(CASE WHEN CAST(sqlc.arg(descending) AS BIGINT) = 1 THEN
            CASE CAST(sqlc.arg(sort) AS TEXT)
                WHEN 'title' THEN LOWER(music_tracks.title)
                WHEN 'artist' THEN LOWER(music_tracks.artist)
                WHEN 'album' THEN LOWER(music_tracks.album)
            END
        END, '') AS TEXT
    ) AS sort_text_desc,
    CAST(
        (CASE WHEN CAST(sqlc.arg(descending) AS BIGINT) = 1 THEN -1 ELSE 1 END) *
        (CASE CAST(sqlc.arg(sort) AS TEXT)
            WHEN 'year' THEN COALESCE(music_tracks.year, 0)
            WHEN 'added' THEN music_tracks.id
            ELSE 0
        END) AS BIGINT
    ) AS sort_num
FROM music_tracks
WHERE
    (CAST(sqlc.arg(filter_album_key) AS BIGINT) = 0 OR music_tracks.album_key = CAST(sqlc.arg(album_key) AS TEXT))
    AND (CAST(sqlc.arg(filter_artist) AS BIGINT) = 0 OR LOWER(music_tracks.album_artist) = LOWER(CAST(sqlc.arg(artist) AS TEXT)))
    AND (CAST(sqlc.arg(filter_genre) AS BIGINT) = 0 OR LOWER(music_tracks.genre) = LOWER(CAST(sqlc.arg(genre) AS TEXT)))
ORDER BY
    sort_text_asc ASC,
    sort_text_desc DESC,
    sort_num,
    LOWER(music_tracks.album_artist),
    LOWER(music_tracks.album),
    COALESCE(music_tracks.disc_no, 0),
    COALESCE(music_tracks.track_no, 0),
    LOWER(music_tracks.title),
    music_tracks.id
LIMIT CAST(sqlc.arg('limit') AS BIGINT) OFFSET CAST(sqlc.arg('offset') AS BIGINT);

-- name: CountMusicTracks :one
SELECT CAST(COUNT(*) AS BIGINT)
FROM music_tracks
WHERE
    (CAST(sqlc.arg(filter_album_key) AS BIGINT) = 0 OR album_key = CAST(sqlc.arg(album_key) AS TEXT))
    AND (CAST(sqlc.arg(filter_artist) AS BIGINT) = 0 OR LOWER(album_artist) = LOWER(CAST(sqlc.arg(artist) AS TEXT)))
    AND (CAST(sqlc.arg(filter_genre) AS BIGINT) = 0 OR LOWER(genre) = LOWER(CAST(sqlc.arg(genre) AS TEXT)));

-- ListMusicTracksAfter is every track in id order, one batch at a time: the
-- stream a non-admin's browse aggregates in Go.
-- name: ListMusicTracksAfter :many
SELECT *
FROM music_tracks
WHERE id > CAST(sqlc.arg(after_id) AS BIGINT)
ORDER BY id
LIMIT CAST(sqlc.arg('limit') AS BIGINT);

-- ListMusicTracksUnder is the track at rel_path and every track under it,
-- what a move rekeys after MoveMusicTracks.
-- name: ListMusicTracksUnder :many
SELECT id, rel_path, album_artist, album
FROM music_tracks
WHERE
    serial = sqlc.arg(serial)
    AND (
        rel_path = sqlc.arg(rel_path)
        OR substr(rel_path, 1, length(sqlc.arg(rel_path)) + 1) = sqlc.arg(rel_path) || '/'
    )
ORDER BY rel_path;

-- name: SetMusicTrackAlbumKey :exec
UPDATE music_tracks SET album_key = sqlc.arg(album_key) WHERE id = sqlc.arg(id);

-- DeleteMusicTrack drops the one row for a file, nothing under it: a
-- backfill's unseen rows.
-- name: DeleteMusicTrack :exec
DELETE FROM music_tracks WHERE serial = sqlc.arg(serial) AND rel_path = sqlc.arg(rel_path);

-- GetMusicTrack is the one row for a file. Cover art reads its cover_source
-- and cover_key: where the picture comes from and its hash, which keys the
-- thumbnail cache.
-- name: GetMusicTrack :one
SELECT *
FROM music_tracks
WHERE serial = sqlc.arg(serial) AND rel_path = sqlc.arg(rel_path);
