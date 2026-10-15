package musicutil

import (
	"cmp"
	"context"
	"database/sql"
	"slices"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

// streamBatch is how many rows a non-admin's browse reads at a time, which
// bounds what it holds besides the groups themselves.
const streamBatch = 500

// ponytail: a non-admin's browse reads every row and checks each one, so it
// costs one pass over the library per request. Join on path_access if it
// measures slow, as searchutil.SearchReadable notes for content search.

func listTracks(params ListTracksParams) (ListTracksResult, error) {
	switch params.Sort {
	case SortAlbumOrder, SortTitle, SortArtist, SortAlbum, SortYear, SortAdded:
	default:
		return ListTracksResult{}, ErrInvalidSort
	}
	q := db.NewQueries(params.DB)
	limit, offset := clampLimit(params.Limit), max(params.Offset, 0)
	list := db.ListMusicTracksParams{
		Sort:       string(params.Sort),
		Descending: boolInt(params.Descending),
	}
	list.FilterAlbumKey, list.AlbumKey = boolInt(params.AlbumKey != ""), params.AlbumKey
	if params.Artist != nil {
		list.FilterArtist, list.Artist = 1, *params.Artist
	}
	if params.Genre != nil {
		list.FilterGenre, list.Genre = 1, *params.Genre
	}

	if params.Access.Principal().IsAdmin {
		list.Limit, list.Offset = int64(limit), int64(offset)
		rows, err := q.ListMusicTracks(params.Ctx, list)
		if err != nil {
			return ListTracksResult{}, err
		}
		total, err := q.CountMusicTracks(params.Ctx, db.CountMusicTracksParams{
			FilterAlbumKey: list.FilterAlbumKey, AlbumKey: list.AlbumKey,
			FilterArtist: list.FilterArtist, Artist: list.Artist,
			FilterGenre: list.FilterGenre, Genre: list.Genre,
		})
		if err != nil {
			return ListTracksResult{}, err
		}
		tracks := make([]Track, 0, len(rows))
		for _, row := range rows {
			tracks = append(tracks, trackFromRow(row.MusicTrack))
		}
		return ListTracksResult{Tracks: tracks, Total: int(total)}, nil
	}

	// Walk the sorted matches in batches, counting every readable one for
	// the total and keeping those that fall on the requested page.
	result := ListTracksResult{Tracks: make([]Track, 0, limit)}
	list.Limit = streamBatch
	for list.Offset = 0; ; list.Offset += streamBatch {
		rows, err := q.ListMusicTracks(params.Ctx, list)
		if err != nil {
			return ListTracksResult{}, err
		}
		for _, row := range rows {
			if !readable(params.Access, row.MusicTrack) {
				continue
			}
			if result.Total >= offset && len(result.Tracks) < limit {
				result.Tracks = append(result.Tracks, trackFromRow(row.MusicTrack))
			}
			result.Total++
		}
		if len(rows) < streamBatch {
			return result, nil
		}
	}
}

func listAlbums(params ListAlbumsParams) (ListAlbumsResult, error) {
	var albums []Album
	if params.Access.Principal().IsAdmin {
		list := db.ListMusicAlbumsParams{}
		if params.Artist != nil {
			list.FilterArtist, list.Artist = 1, *params.Artist
		}
		rows, err := db.NewQueries(params.DB).ListMusicAlbums(params.Ctx, list)
		if err != nil {
			return ListAlbumsResult{}, err
		}
		albums = make([]Album, 0, len(rows))
		for _, row := range rows {
			albums = append(albums, Album{
				AlbumKey: row.AlbumKey, Title: row.Title, AlbumArtist: row.AlbumArtist,
				Year: int(row.Year.Int64), TrackCount: int(row.TrackCount), DurationMs: row.DurationMs,
				CoverSerial: row.CoverSerial, CoverPath: row.CoverPath,
			})
		}
	} else {
		groups := map[string]*albumGroup{}
		err := streamReadable(params.Ctx, params.DB, params.Access, func(row db.MusicTrack) {
			if params.Artist != nil && sqlLower(row.AlbumArtist) != sqlLower(*params.Artist) {
				return
			}
			g, seen := groups[row.AlbumKey]
			if !seen {
				g = &albumGroup{album: Album{AlbumKey: row.AlbumKey}}
				groups[row.AlbumKey] = g
			}
			a := &g.album
			a.Title = minString(a.Title, seen, row.Album)
			a.AlbumArtist = minString(a.AlbumArtist, seen, row.AlbumArtist)
			if row.Year.Valid && (a.Year == 0 || int(row.Year.Int64) < a.Year) {
				a.Year = int(row.Year.Int64)
			}
			a.TrackCount++
			a.DurationMs += row.DurationMs.Int64
			g.cover.consider(row)
		})
		if err != nil {
			return ListAlbumsResult{}, err
		}
		albums = make([]Album, 0, len(groups))
		for _, g := range groups {
			g.album.CoverSerial, g.album.CoverPath = g.cover.serial, g.cover.relPath
			albums = append(albums, g.album)
		}
		slices.SortFunc(albums, func(a, b Album) int {
			return cmp.Or(
				cmp.Compare(sqlLower(a.AlbumArtist), sqlLower(b.AlbumArtist)),
				cmp.Compare(sqlLower(a.Title), sqlLower(b.Title)),
				cmp.Compare(a.AlbumKey, b.AlbumKey),
			)
		})
	}
	return ListAlbumsResult{Albums: pageOf(albums, params.Offset, params.Limit), Total: len(albums)}, nil
}

func listArtists(params ListArtistsParams) (ListArtistsResult, error) {
	var artists []Artist
	if params.Access.Principal().IsAdmin {
		rows, err := db.NewQueries(params.DB).ListMusicArtists(params.Ctx)
		if err != nil {
			return ListArtistsResult{}, err
		}
		artists = make([]Artist, 0, len(rows))
		for _, row := range rows {
			artists = append(artists, Artist{
				Name: row.Name, AlbumCount: int(row.AlbumCount), TrackCount: int(row.TrackCount),
				CoverSerial: row.CoverSerial, CoverPath: row.CoverPath,
			})
		}
	} else {
		groups := map[string]*artistGroup{}
		err := streamReadable(params.Ctx, params.DB, params.Access, func(row db.MusicTrack) {
			key := sqlLower(row.AlbumArtist)
			g, seen := groups[key]
			if !seen {
				g = &artistGroup{albums: map[string]struct{}{}}
				groups[key] = g
			}
			g.artist.Name = minString(g.artist.Name, seen, row.AlbumArtist)
			g.artist.TrackCount++
			g.albums[row.AlbumKey] = struct{}{}
			g.cover.consider(row)
		})
		if err != nil {
			return ListArtistsResult{}, err
		}
		artists = make([]Artist, 0, len(groups))
		for _, g := range groups {
			g.artist.AlbumCount = len(g.albums)
			g.artist.CoverSerial, g.artist.CoverPath = g.cover.serial, g.cover.relPath
			artists = append(artists, g.artist)
		}
		slices.SortFunc(artists, func(a, b Artist) int {
			return cmp.Compare(sqlLower(a.Name), sqlLower(b.Name))
		})
	}
	return ListArtistsResult{Artists: pageOf(artists, params.Offset, params.Limit), Total: len(artists)}, nil
}

func listGenres(params ListGenresParams) (ListGenresResult, error) {
	if params.Access.Principal().IsAdmin {
		rows, err := db.NewQueries(params.DB).ListMusicGenres(params.Ctx)
		if err != nil {
			return ListGenresResult{}, err
		}
		genres := make([]Genre, 0, len(rows))
		for _, row := range rows {
			genres = append(genres, Genre{Name: row.Name, TrackCount: int(row.TrackCount)})
		}
		return ListGenresResult{Genres: genres}, nil
	}
	groups := map[string]*Genre{}
	err := streamReadable(params.Ctx, params.DB, params.Access, func(row db.MusicTrack) {
		key := sqlLower(row.Genre)
		g, seen := groups[key]
		if !seen {
			g = &Genre{}
			groups[key] = g
		}
		g.Name = minString(g.Name, seen, row.Genre)
		g.TrackCount++
	})
	if err != nil {
		return ListGenresResult{}, err
	}
	genres := make([]Genre, 0, len(groups))
	for _, g := range groups {
		genres = append(genres, *g)
	}
	slices.SortFunc(genres, func(a, b Genre) int { return cmp.Compare(sqlLower(a.Name), sqlLower(b.Name)) })
	return ListGenresResult{Genres: genres}, nil
}

// streamReadable hands every row the caller can read to visit, reading the
// table in id order a batch at a time.
func streamReadable(ctx context.Context, sqlDB *sql.DB, access accessutil.Access, visit func(db.MusicTrack)) error {
	q := db.NewQueries(sqlDB)
	var after int64
	for {
		rows, err := q.ListMusicTracksAfter(ctx, db.ListMusicTracksAfterParams{AfterID: after, Limit: streamBatch})
		if err != nil {
			return err
		}
		for _, row := range rows {
			if readable(access, row) {
				visit(row)
			}
		}
		if len(rows) < streamBatch {
			return nil
		}
		after = rows[len(rows)-1].ID
	}
}

// readable reports whether the caller may see a track.
func readable(access accessutil.Access, row db.MusicTrack) bool {
	return access.Check(row.Serial, row.RelPath, accessutil.Read).Readable
}
