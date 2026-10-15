package musicutil_test

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/musicutil"
)

// TestMusicOnPostgres runs the scan and every browse query on PostgreSQL,
// where they are shared sqlc queries, and checks they agree with SQLite.
// Search is FTS5: it is refused by name until #2958.
func TestMusicOnPostgres(t *testing.T) {
	database, err := db.ConnectToPostgres(dbtest.PostgresURL(t))
	if err != nil {
		t.Fatalf("ConnectToPostgres: %v", err)
	}
	t.Cleanup(func() { _ = database.Db.Close() })
	sqlite := library(t)
	ctx := context.Background()
	seed(t, database.Db,
		track{path: "shared/mixed/1.flac", title: "Alpha", artist: "Ann", album: "Mixed", genre: "Rock", trackNo: 1, year: 2001},
		track{path: "shared/mixed/2.flac", title: "beta", artist: "Ann", album: "Mixed", genre: "rock", trackNo: 2},
		track{path: "shared/solo/1.flac", title: "Gamma", artist: "Bo", album: "Solo", genre: "Jazz", trackNo: 1, year: 1990},
		track{path: "private/mixed/3.flac", title: "Delta", artist: "Ann", album: "Mixed", genre: "Rock", trackNo: 3, year: 1980, cover: true},
		track{path: "private/secret/1.flac", title: "Epsilon", artist: "Cy", album: "Secret", genre: "Metal", trackNo: 1, cover: true},
	)
	admin := adminAccess(t)

	for _, sort := range []musicutil.TrackSort{musicutil.SortAlbumOrder, musicutil.SortTitle, musicutil.SortYear, musicutil.SortAdded} {
		for _, desc := range []bool{false, true} {
			params := musicutil.ListTracksParams{Ctx: ctx, Access: admin, Sort: sort, Descending: desc}
			params.DB = sqlite.Db
			want, err := musicutil.ListTracks(params)
			if err != nil {
				t.Fatal(err)
			}
			params.DB = database.Db
			got, err := musicutil.ListTracks(params)
			if err != nil {
				t.Fatalf("ListTracks sort %q on PostgreSQL: %v", sort, err)
			}
			if !reflect.DeepEqual(titles(got.Tracks), titles(want.Tracks)) || got.Total != want.Total {
				t.Errorf("sort %q desc %v: PostgreSQL %v, SQLite %v", sort, desc, titles(got.Tracks), titles(want.Tracks))
			}
		}
	}
	albums, err := musicutil.ListAlbums(musicutil.ListAlbumsParams{Ctx: ctx, DB: database.Db, Access: admin})
	if err != nil || albums.Total != 3 {
		t.Errorf("ListAlbums = %+v, %v; want 3 albums", albums, err)
	}
	artists, err := musicutil.ListArtists(musicutil.ListArtistsParams{Ctx: ctx, DB: database.Db, Access: admin})
	if err != nil || artists.Total != 3 {
		t.Errorf("ListArtists = %+v, %v; want 3 artists", artists, err)
	}
	genres, err := musicutil.ListGenres(musicutil.ListGenresParams{Ctx: ctx, DB: database.Db, Access: admin})
	if err != nil || len(genres.Genres) != 3 {
		t.Errorf("ListGenres = %+v, %v; want 3 genres", genres, err)
	}
	if _, err := musicutil.MovePath(musicutil.MovePathParams{Ctx: ctx, DB: database.Db, Serial: usbSerial, OldPath: "shared", NewPath: "moved"}); err != nil {
		t.Errorf("MovePath: %v", err)
	}

	_, err = musicutil.Search(musicutil.SearchParams{Ctx: ctx, DB: database.Db, Access: admin, Query: "ann"})
	var unsupported *db.UnsupportedError
	if !errors.As(err, &unsupported) || unsupported.Issue != 2958 {
		t.Errorf("Search = %v, want a *db.UnsupportedError naming #2958", err)
	}
}
