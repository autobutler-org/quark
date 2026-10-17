package musicutil_test

import (
	"context"
	"database/sql"
	"errors"
	"reflect"
	"strconv"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/musicutil"
)

// track is a row to seed.
type track struct {
	path, title, artist, album, genre string
	trackNo, year                     int
	cover                             bool
}

// seed stores tracks on the USB drive, keyed the way a scan keys them.
func seed(t *testing.T, sqlDB *sql.DB, tracks ...track) {
	t.Helper()
	fsys := memFS(t, nil)
	for _, tr := range tracks {
		var picture []byte
		if tr.cover {
			picture = []byte("art of " + tr.album)
		}
		comments := []string{"TITLE=" + tr.title, "ARTIST=" + tr.artist, "ALBUM=" + tr.album, "GENRE=" + tr.genre}
		if tr.trackNo > 0 {
			comments = append(comments, "TRACKNUMBER="+string(rune('0'+tr.trackNo)))
		}
		if tr.year > 0 {
			comments = append(comments, "DATE="+strconv.Itoa(tr.year))
		}
		write(t, fsys, tr.path, flacFile(60, picture, comments...))
		if _, err := musicutil.IndexTrack(musicutil.IndexTrackParams{
			Ctx: context.Background(), DB: sqlDB, FS: fsys, Serial: usbSerial, RelPath: tr.path,
		}); err != nil {
			t.Fatal(err)
		}
	}
}

// library is a small library split between a shared and a private folder.
// Album "Mixed" has tracks on both sides.
func library(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	database := newDB(t)
	seed(t, database.Db,
		track{path: "shared/mixed/1.flac", title: "Alpha", artist: "Ann", album: "Mixed", genre: "Rock", trackNo: 1, year: 2001},
		track{path: "shared/mixed/2.flac", title: "beta", artist: "Ann", album: "Mixed", genre: "rock", trackNo: 2},
		track{path: "shared/solo/1.flac", title: "Gamma", artist: "Bo", album: "Solo", genre: "Jazz", trackNo: 1, year: 1990},
		track{path: "private/mixed/3.flac", title: "Delta", artist: "Ann", album: "Mixed", genre: "Rock", trackNo: 3, year: 1980, cover: true},
		track{path: "private/secret/1.flac", title: "Epsilon", artist: "Cy", album: "Secret", genre: "Metal", trackNo: 1, cover: true},
	)
	return database
}

func titles(tracks []musicutil.Track) []string {
	out := make([]string, 0, len(tracks))
	for _, tr := range tracks {
		out = append(out, tr.Title)
	}
	return out
}

// TestListTracks_SortsPagesAndFilters checks the admin's SQL path: sorts,
// direction, filters and the total.
func TestListTracks_SortsPagesAndFilters(t *testing.T) {
	database := library(t)
	ctx := context.Background()
	ann, rock := "ANN", "ROCK"
	cases := []struct {
		name   string
		params musicutil.ListTracksParams
		want   []string
		total  int
	}{
		{"album order", musicutil.ListTracksParams{}, []string{"Alpha", "beta", "Delta", "Gamma", "Epsilon"}, 5},
		{"title", musicutil.ListTracksParams{Sort: musicutil.SortTitle}, []string{"Alpha", "beta", "Delta", "Epsilon", "Gamma"}, 5},
		{"title descending", musicutil.ListTracksParams{Sort: musicutil.SortTitle, Descending: true}, []string{"Gamma", "Epsilon", "Delta", "beta", "Alpha"}, 5},
		{"year", musicutil.ListTracksParams{Sort: musicutil.SortYear}, []string{"beta", "Epsilon", "Delta", "Gamma", "Alpha"}, 5},
		{"page", musicutil.ListTracksParams{Sort: musicutil.SortTitle, Offset: 1, Limit: 2}, []string{"beta", "Delta"}, 5},
		{"artist filter", musicutil.ListTracksParams{Artist: &ann}, []string{"Alpha", "beta", "Delta"}, 3},
		{"genre filter", musicutil.ListTracksParams{Genre: &rock, Sort: musicutil.SortTitle}, []string{"Alpha", "beta", "Delta"}, 3},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			c.params.Ctx, c.params.DB, c.params.Access = ctx, database.Db, adminAccess(t)
			got, err := musicutil.ListTracks(c.params)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(titles(got.Tracks), c.want) || got.Total != c.total {
				t.Errorf("tracks %v total %d, want %v total %d", titles(got.Tracks), got.Total, c.want, c.total)
			}
		})
	}

	_, err := musicutil.ListTracks(musicutil.ListTracksParams{Ctx: ctx, DB: database.Db, Access: adminAccess(t), Sort: "bogus"})
	if !errors.Is(err, musicutil.ErrInvalidSort) {
		t.Errorf("unknown sort err = %v, want ErrInvalidSort", err)
	}
}

// TestBrowse_MemberSeesOnlyReadableTracks checks that a non-admin's tracks,
// counts, years and covers come only from what they can read.
func TestBrowse_MemberSeesOnlyReadableTracks(t *testing.T) {
	database := library(t)
	ctx := context.Background()
	member := memberAccess(t, database, "shared")

	tracks, err := musicutil.ListTracks(musicutil.ListTracksParams{Ctx: ctx, DB: database.Db, Access: member, Sort: musicutil.SortTitle, Offset: 1, Limit: 1})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(titles(tracks.Tracks), []string{"beta"}) || tracks.Total != 3 {
		t.Errorf("member tracks %v total %d, want [beta] of 3", titles(tracks.Tracks), tracks.Total)
	}

	albums, err := musicutil.ListAlbums(musicutil.ListAlbumsParams{Ctx: ctx, DB: database.Db, Access: member})
	if err != nil {
		t.Fatal(err)
	}
	if albums.Total != 2 || len(albums.Albums) != 2 {
		t.Fatalf("member albums = %+v, want Mixed and Solo", albums)
	}
	mixed := albums.Albums[0]
	if mixed.Title != "Mixed" || mixed.TrackCount != 2 || mixed.DurationMs != 120_000 || mixed.Year != 2001 {
		t.Errorf("Mixed = %+v, want 2 tracks, 120 s, year 2001 from the shared tracks only", mixed)
	}
	if mixed.CoverPath != "shared/mixed/1.flac" || mixed.CoverSerial != usbSerial {
		t.Errorf("Mixed cover = %s:%s, want a shared track, not the private one with art", mixed.CoverSerial, mixed.CoverPath)
	}

	artists, err := musicutil.ListArtists(musicutil.ListArtistsParams{Ctx: ctx, DB: database.Db, Access: member})
	if err != nil {
		t.Fatal(err)
	}
	wantArtists := []musicutil.Artist{
		{Name: "Ann", AlbumCount: 1, TrackCount: 2, CoverSerial: usbSerial, CoverPath: "shared/mixed/1.flac"},
		{Name: "Bo", AlbumCount: 1, TrackCount: 1, CoverSerial: usbSerial, CoverPath: "shared/solo/1.flac"},
	}
	if !reflect.DeepEqual(artists.Artists, wantArtists) || artists.Total != 2 {
		t.Errorf("member artists = %+v, want %+v", artists, wantArtists)
	}

	genres, err := musicutil.ListGenres(musicutil.ListGenresParams{Ctx: ctx, DB: database.Db, Access: member})
	if err != nil {
		t.Fatal(err)
	}
	wantGenres := []musicutil.Genre{{Name: "Jazz", TrackCount: 1}, {Name: "Rock", TrackCount: 2}}
	if !reflect.DeepEqual(genres.Genres, wantGenres) {
		t.Errorf("member genres = %+v, want %+v", genres.Genres, wantGenres)
	}
}

// TestBrowse_FullAccessMatchesAdmin holds the Go aggregation to the SQL one:
// a member who can read the whole drive sees exactly what an admin sees.
func TestBrowse_FullAccessMatchesAdmin(t *testing.T) {
	database := library(t)
	ctx := context.Background()
	admin, member := adminAccess(t), memberAccess(t, database, "")
	ann := "ann"

	for name, list := range map[string]func(accessutil.Access) (any, error){
		"tracks": func(a accessutil.Access) (any, error) {
			return musicutil.ListTracks(musicutil.ListTracksParams{Ctx: ctx, DB: database.Db, Access: a, Sort: musicutil.SortYear, Descending: true, Limit: 3})
		},
		"albums": func(a accessutil.Access) (any, error) {
			return musicutil.ListAlbums(musicutil.ListAlbumsParams{Ctx: ctx, DB: database.Db, Access: a})
		},
		"albums by artist": func(a accessutil.Access) (any, error) {
			return musicutil.ListAlbums(musicutil.ListAlbumsParams{Ctx: ctx, DB: database.Db, Access: a, Artist: &ann})
		},
		"artists": func(a accessutil.Access) (any, error) {
			return musicutil.ListArtists(musicutil.ListArtistsParams{Ctx: ctx, DB: database.Db, Access: a, Offset: 1, Limit: 1})
		},
		"genres": func(a accessutil.Access) (any, error) {
			return musicutil.ListGenres(musicutil.ListGenresParams{Ctx: ctx, DB: database.Db, Access: a})
		},
	} {
		t.Run(name, func(t *testing.T) {
			want, err := list(admin)
			if err != nil {
				t.Fatal(err)
			}
			got, err := list(member)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, want) {
				t.Errorf("member sees %+v\nadmin sees  %+v", got, want)
			}
		})
	}
}

// TestBrowse_NobodySeesNothing denies a member with no grants every track.
func TestBrowse_NobodySeesNothing(t *testing.T) {
	database := library(t)
	member := memberAccess(t, database)
	albums, err := musicutil.ListAlbums(musicutil.ListAlbumsParams{Ctx: context.Background(), DB: database.Db, Access: member})
	if err != nil || albums.Total != 0 || len(albums.Albums) != 0 {
		t.Errorf("ListAlbums = %+v, %v; want nothing", albums, err)
	}
}
