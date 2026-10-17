package musicutil

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/searchutil"
)

func search(params SearchParams) (SearchResultPage, error) {
	if err := db.RequireSQLite(params.DB, "Music search", 2958); err != nil {
		return SearchResultPage{}, err
	}
	query := searchutil.SanitizeQuery(params.Query)
	limit := clampLimit(params.Limit)
	if params.Access.Principal().IsAdmin {
		results, err := searchPage(params.Ctx, params.DB, query, limit, 0)
		return SearchResultPage{Results: results}, err
	}
	page, err := searchutil.ReadablePage(searchutil.ReadablePageParams[SearchResult]{
		Limit: limit,
		Fetch: func(limit, offset int) ([]SearchResult, error) {
			return searchPage(params.Ctx, params.DB, query, limit, offset)
		},
		Readable: func(r SearchResult) bool {
			return params.Access.Check(r.Track.Serial, r.Track.RelPath, accessutil.Read).Readable
		},
	})
	return SearchResultPage(page), err
}

// searchPage returns up to limit matches ranked after the first offset.
//
// Raw SQL rather than sqlc: MATCH, the bm25 rank ordering it implies and
// snippet() are FTS5 extensions sqlc's SQLite parser does not accept, the
// exception AGENTS.md names for searchutil. music_tracks_fts exists only in
// the SQLite schema, so search checks db.RequireSQLite first.
func searchPage(ctx context.Context, sqlDB *sql.DB, query string, limit, offset int) ([]SearchResult, error) {
	rows, err := sqlDB.QueryContext(ctx, `
		SELECT
		    t.id, t.serial, t.rel_path, t.size, t.mtime, t.scanner_version,
		    t.title, t.artist, t.album_artist, t.album, t.album_key, t.genre,
		    t.track_no, t.disc_no, t.year, t.duration_ms, t.duration_exact,
		    t.cover_source, t.cover_key,
		    snippet(music_tracks_fts, -1, '<b>', '</b>', '…', 12) AS snippet
		FROM music_tracks_fts
		JOIN music_tracks t ON t.id = music_tracks_fts.rowid
		WHERE music_tracks_fts MATCH ?
		ORDER BY rank, t.id
		LIMIT ? OFFSET ?`, query, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("music search: %w", err)
	}
	defer func() { _ = rows.Close() }()

	results := []SearchResult{}
	for rows.Next() {
		var t db.MusicTrack
		var snippet string
		if err := rows.Scan(
			&t.ID, &t.Serial, &t.RelPath, &t.Size, &t.Mtime, &t.ScannerVersion,
			&t.Title, &t.Artist, &t.AlbumArtist, &t.Album, &t.AlbumKey, &t.Genre,
			&t.TrackNo, &t.DiscNo, &t.Year, &t.DurationMs, &t.DurationExact,
			&t.CoverSource, &t.CoverKey,
			&snippet,
		); err != nil {
			return nil, fmt.Errorf("scan music search result: %w", err)
		}
		results = append(results, SearchResult{Track: trackFromRow(t), Snippet: snippet})
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("music search: %w", err)
	}
	return results, nil
}
