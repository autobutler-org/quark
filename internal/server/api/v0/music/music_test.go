package v0_music_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_music "github.com/autobutler-org/quark/internal/server/api/v0/music"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// systemDevice is the internal drive at "/", whose files directory is the one
// storageutil.GetFilesDir resolves under HOME.
type systemDevice struct{}

func (systemDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// track is a library row to seed on the internal drive.
type track struct {
	path, title, artist, album, genre string
	trackNo                           int64
	cover                             bool
}

// library is split between a folder the member can read and one they cannot.
// Album "Mixed" has a track on each side; "Secret", its artist Cy and the
// Metal genre exist only on the private side.
var library = []track{
	{path: "shared/mixed/1.flac", title: "Alpha", artist: "Ann", album: "Mixed", genre: "Rock", trackNo: 1},
	{path: "shared/mixed/2.flac", title: "Beta", artist: "Ann", album: "Mixed", genre: "Rock", trackNo: 2},
	{path: "shared/solo/1.flac", title: "Gamma", artist: "Bo", album: "Solo", genre: "Jazz", trackNo: 1},
	{path: "private/mixed/3.flac", title: "Delta", artist: "Ann", album: "Mixed", genre: "Rock", trackNo: 3, cover: true},
	{path: "private/secret/1.flac", title: "Epsilon", artist: "Cy", album: "Secret", genre: "Metal", trackNo: 1, cover: true},
}

// musicHarness serves the music routes over a migrated database and the real
// admin gate, acting as whoever principal names: the admin or a member who
// can read only "shared".
type musicHarness struct {
	engine    *gin.Engine
	database  *db.DatabaseSqlc
	principal *accessutil.Principal
	username  *string
	admin     accessutil.Principal
	member    accessutil.Principal
}

func newMusicHarness(t *testing.T) musicHarness {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	if _, err := storageutil.GetFilesDir(); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	database := dbtest.NewDB(t)
	admin, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "admin", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.PromoteToAdmin(ctx, "admin"); err != nil {
		t.Fatal(err)
	}
	member, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "member", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		RelPath: "shared",
		UserID:  sql.NullInt64{Int64: member.ID, Valid: true},
		Level:   accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}
	for _, tr := range library {
		row := db.UpsertMusicTrackParams{
			RelPath: tr.path, ScannerVersion: musicutil.ScannerVersion,
			Title: tr.title, Artist: tr.artist, AlbumArtist: tr.artist, Album: tr.album,
			AlbumKey: tr.artist + "/" + tr.album, Genre: tr.genre,
			TrackNo:    sql.NullInt64{Int64: tr.trackNo, Valid: true},
			DurationMs: sql.NullInt64{Int64: 60_000, Valid: true},
		}
		if tr.cover {
			row.CoverSource, row.CoverKey = "embedded", "key-"+tr.album
		}
		if _, err := database.Queries.UpsertMusicTrack(ctx, row); err != nil {
			t.Fatal(err)
		}
	}
	// The queue runs nothing, so a queued scan stays pending.
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database})
	queue.Register(jobutil.RegisterParams{Kind: musicutil.RescanKind, Handler: jobutil.Handler{}})
	deps := deputil.NewDependencies().
		WithStorageService(storageutil.NewStorageService(systemDevice{})).
		WithDatabase(database).
		WithMetadataStore(vfs.NewSQLiteMetadataStore(database.Db)).
		WithJobQueue(queue)

	h := musicHarness{
		database:  database,
		principal: &accessutil.Principal{},
		username:  new(string),
		admin:     accessutil.Principal{UserID: admin.ID, IsAdmin: true},
		member:    accessutil.Principal{UserID: member.ID},
	}
	h.as(h.admin)
	gin.SetMode(gin.TestMode)
	h.engine = gin.New()
	h.engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *h.principal)
		c = ctxutil.With(c, "username", *h.username)
		c.Next()
	})
	group := h.engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_music.NewRouter())
	serverutil.RegisterRouterWithGroup(group.Group("", middleware.RequireAdmin(deps)), v0_music.NewAdminRouter())
	return h
}

// as makes the following requests come from p.
func (h musicHarness) as(p accessutil.Principal) {
	*h.principal = p
	*h.username = "member"
	if p.IsAdmin {
		*h.username = "admin"
	}
}

// get sends a GET and decodes a 200 into out. It returns the status.
func (h musicHarness) get(t *testing.T, path string, out any) int {
	t.Helper()
	return h.send(t, http.MethodGet, path, out)
}

func (h musicHarness) send(t *testing.T, method, path string, out any) int {
	t.Helper()
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(method, path, nil))
	if (w.Code == http.StatusOK || w.Code == http.StatusAccepted) && out != nil {
		if err := json.Unmarshal(w.Body.Bytes(), out); err != nil {
			t.Fatalf("decode %s: %v", w.Body.String(), err)
		}
	}
	return w.Code
}

func trackTitles(tracks []musicutil.Track) []string {
	out := []string{}
	for _, tr := range tracks {
		out = append(out, tr.Title)
	}
	return out
}

func TestListTracks(t *testing.T) {
	h := newMusicHarness(t)
	cases := []struct {
		name   string
		member bool
		query  string
		want   []string
		total  int
	}{
		{name: "admin sees every track in album order", query: "", want: []string{"Alpha", "Beta", "Delta", "Gamma", "Epsilon"}, total: 5},
		{name: "member sees only shared tracks", member: true, query: "", want: []string{"Alpha", "Beta", "Gamma"}, total: 3},
		{name: "sort and order", query: "?sort=title&order=desc", want: []string{"Gamma", "Epsilon", "Delta", "Beta", "Alpha"}, total: 5},
		{name: "page", query: "?sort=title&offset=1&limit=2", want: []string{"Beta", "Delta"}, total: 5},
		{name: "member page counts only readable tracks", member: true, query: "?sort=title&offset=1&limit=1", want: []string{"Beta"}, total: 3},
		{name: "artist filter ignores case", query: "?artist=ann", want: []string{"Alpha", "Beta", "Delta"}, total: 3},
		{name: "genre filter", query: "?genre=metal", want: []string{"Epsilon"}, total: 1},
		{name: "member genre filter hides private", member: true, query: "?genre=metal", want: []string{}, total: 0},
		{name: "album filter", member: true, query: "?albumKey=Ann/Mixed", want: []string{"Alpha", "Beta"}, total: 2},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h.as(h.admin)
			if tc.member {
				h.as(h.member)
			}
			var got v0_music.TracksResponse
			if code := h.get(t, "/api/v0/music/tracks"+tc.query, &got); code != http.StatusOK {
				t.Fatalf("status = %d, want 200", code)
			}
			if titles := trackTitles(got.Tracks); !reflect.DeepEqual(titles, tc.want) || got.Total != tc.total {
				t.Errorf("got %v (total %d), want %v (total %d)", titles, got.Total, tc.want, tc.total)
			}
		})
	}
	for _, query := range []string{"?sort=bogus", "?order=sideways", "?limit=-1", "?offset=x"} {
		if code := h.get(t, "/api/v0/music/tracks"+query, nil); code != http.StatusBadRequest {
			t.Errorf("%s = %d, want 400", query, code)
		}
	}
}

func TestListAlbums(t *testing.T) {
	h := newMusicHarness(t)
	var got v0_music.AlbumsResponse
	if code := h.get(t, "/api/v0/music/albums", &got); code != http.StatusOK || got.Total != 3 {
		t.Fatalf("admin = %d with %d albums, want 200 with 3", code, got.Total)
	}
	if mixed := got.Albums[0]; mixed.Title != "Mixed" || mixed.TrackCount != 3 || mixed.CoverPath != "private/mixed/3.flac" {
		t.Errorf("admin's Mixed = %+v, want 3 tracks and the private cover", mixed)
	}

	// The member sees Mixed through its shared tracks alone: its count and
	// cover never name the private one, and Secret is not there at all.
	h.as(h.member)
	got = v0_music.AlbumsResponse{}
	if code := h.get(t, "/api/v0/music/albums", &got); code != http.StatusOK {
		t.Fatalf("member = %d, want 200", code)
	}
	var names []string
	for _, a := range got.Albums {
		names = append(names, a.Title)
	}
	if !reflect.DeepEqual(names, []string{"Mixed", "Solo"}) || got.Total != 2 {
		t.Fatalf("member albums = %v (total %d), want [Mixed Solo]", names, got.Total)
	}
	if mixed := got.Albums[0]; mixed.TrackCount != 2 || mixed.DurationMs != 120_000 || mixed.CoverPath != "shared/mixed/1.flac" {
		t.Errorf("member's Mixed = %+v, want 2 tracks, 120000 ms and a shared cover", mixed)
	}

	got = v0_music.AlbumsResponse{}
	if code := h.get(t, "/api/v0/music/albums?artist=BO", &got); code != http.StatusOK || len(got.Albums) != 1 || got.Albums[0].Title != "Solo" {
		t.Errorf("artist filter = %d %+v, want Solo alone", code, got.Albums)
	}
	if code := h.get(t, "/api/v0/music/albums?limit=many", nil); code != http.StatusBadRequest {
		t.Errorf("bad limit = %d, want 400", code)
	}
}

func TestListArtists(t *testing.T) {
	h := newMusicHarness(t)
	var got v0_music.ArtistsResponse
	if code := h.get(t, "/api/v0/music/artists", &got); code != http.StatusOK || got.Total != 3 {
		t.Fatalf("admin = %d with %d artists, want 200 with 3", code, got.Total)
	}

	h.as(h.member)
	got = v0_music.ArtistsResponse{}
	if code := h.get(t, "/api/v0/music/artists", &got); code != http.StatusOK {
		t.Fatalf("member = %d, want 200", code)
	}
	want := []musicutil.Artist{
		{Name: "Ann", AlbumCount: 1, TrackCount: 2, CoverPath: "shared/mixed/1.flac"},
		{Name: "Bo", AlbumCount: 1, TrackCount: 1, CoverPath: "shared/solo/1.flac"},
	}
	if !reflect.DeepEqual(got.Artists, want) || got.Total != 2 {
		t.Errorf("member artists = %+v (total %d), want %+v", got.Artists, got.Total, want)
	}

	got = v0_music.ArtistsResponse{}
	if code := h.get(t, "/api/v0/music/artists?offset=1&limit=1", &got); code != http.StatusOK || len(got.Artists) != 1 || got.Artists[0].Name != "Bo" || got.Total != 2 {
		t.Errorf("paged = %d %+v (total %d), want Bo of 2", code, got.Artists, got.Total)
	}
}

func TestListGenres(t *testing.T) {
	h := newMusicHarness(t)
	var got v0_music.GenresResponse
	if code := h.get(t, "/api/v0/music/genres", &got); code != http.StatusOK {
		t.Fatalf("admin = %d, want 200", code)
	}
	want := []musicutil.Genre{{Name: "Jazz", TrackCount: 1}, {Name: "Metal", TrackCount: 1}, {Name: "Rock", TrackCount: 3}}
	if !reflect.DeepEqual(got.Genres, want) {
		t.Errorf("admin genres = %+v, want %+v", got.Genres, want)
	}

	h.as(h.member)
	got = v0_music.GenresResponse{}
	if code := h.get(t, "/api/v0/music/genres", &got); code != http.StatusOK {
		t.Fatalf("member = %d, want 200", code)
	}
	want = []musicutil.Genre{{Name: "Jazz", TrackCount: 1}, {Name: "Rock", TrackCount: 2}}
	if !reflect.DeepEqual(got.Genres, want) {
		t.Errorf("member genres = %+v, want %+v", got.Genres, want)
	}
}

func TestSearchMusic(t *testing.T) {
	h := newMusicHarness(t)
	search := func(t *testing.T, query string) []string {
		t.Helper()
		var got v0_music.SearchResponse
		if code := h.get(t, "/api/v0/music/search?q="+query, &got); code != http.StatusOK {
			t.Fatalf("search %q = %d, want 200", query, code)
		}
		titles := []string{}
		for _, r := range got.Results {
			titles = append(titles, r.Track.Title)
		}
		return titles
	}
	if got := search(t, "epsilon"); !reflect.DeepEqual(got, []string{"Epsilon"}) {
		t.Errorf("admin epsilon = %v, want [Epsilon]", got)
	}
	if got := search(t, "ann"); len(got) != 3 {
		t.Errorf("admin ann = %v, want 3 tracks", got)
	}

	h.as(h.member)
	if got := search(t, "epsilon"); len(got) != 0 {
		t.Errorf("member epsilon = %v, want nothing: the track is private", got)
	}
	if got := search(t, "ann"); len(got) != 2 {
		t.Errorf("member ann = %v, want the 2 shared tracks", got)
	}
	for _, query := range []string{"", "%20", "ann&limit=x"} {
		if code := h.get(t, "/api/v0/music/search?q="+query, nil); code != http.StatusBadRequest {
			t.Errorf("search %q = %d, want 400", query, code)
		}
	}
}

func TestStatusAndRescan(t *testing.T) {
	h := newMusicHarness(t)
	var status musicutil.StatusResult
	if code := h.get(t, "/api/v0/music/status", &status); code != http.StatusOK || status.TrackCount != 5 || status.ScanJobID != nil {
		t.Fatalf("admin status = %d %+v, want 5 tracks and no scan", code, status)
	}

	// Only an admin may queue a scan; the member's request queues nothing.
	h.as(h.member)
	if code := h.send(t, http.MethodPost, "/api/v0/music/rescan", nil); code != http.StatusForbidden {
		t.Fatalf("member rescan = %d, want 403", code)
	}
	status = musicutil.StatusResult{}
	if code := h.get(t, "/api/v0/music/status", &status); code != http.StatusOK || status.TrackCount != 3 || status.ScanJobID != nil {
		t.Fatalf("member status = %d %+v, want 3 tracks and no scan", code, status)
	}

	h.as(h.admin)
	var job jobutil.Job
	if code := h.send(t, http.MethodPost, "/api/v0/music/rescan", &job); code != http.StatusAccepted {
		t.Fatalf("admin rescan = %d, want 202", code)
	}
	if job.Kind != musicutil.RescanKind || job.Status != jobutil.StatusPending {
		t.Errorf("rescan queued %+v, want a pending %s job", job, musicutil.RescanKind)
	}

	// Anyone's status names the scan in progress.
	h.as(h.member)
	status = musicutil.StatusResult{}
	if code := h.get(t, "/api/v0/music/status", &status); code != http.StatusOK || status.ScanJobID == nil || *status.ScanJobID != job.ID {
		t.Errorf("status while scanning = %d %+v, want scan job %d", code, status, job.ID)
	}
}
