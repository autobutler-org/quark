package v0_albums_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_albums "github.com/autobutler-org/quark/internal/server/api/v0/albums"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// systemDevice is the internal drive at "/", whose files directory lives under
// HOME.
type systemDevice struct{}

func (systemDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// TestAlbums_Access shows a non-admin only the album items they can read, and
// counts only those, in every response that carries a count, while an admin's
// albums are unchanged (#1904). Albums stay shared until #1912.
func TestAlbums_Access(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	if _, err := storageutil.GetFilesDir(); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	ctx := context.Background()
	q := database.Queries
	user, err := q.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	trip, err := albumutil.CreateAlbum(ctx, albumutil.CreateAlbumParams{Queries: q, Name: "trip"})
	if err != nil {
		t.Fatal(err)
	}
	day, err := albumutil.CreateAlbum(ctx, albumutil.CreateAlbumParams{
		Queries: q, Name: "day1", ParentID: sql.NullInt64{Int64: trip.Album.ID, Valid: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range []struct {
		album int64
		path  string
	}{
		{trip.Album.ID, "shared/a.jpg"},
		{trip.Album.ID, "private/b.jpg"},
		{day.Album.ID, "private/c.jpg"},
	} {
		if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: item.album, RelPath: item.path}); err != nil {
			t.Fatal(err)
		}
	}

	deps := deputil.NewDependencies().
		WithStorageService(storageutil.NewStorageService(systemDevice{})).
		WithDatabase(database)
	principal := accessutil.System
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_albums.NewRouter())

	do := func(method, path, body string, out any) int {
		t.Helper()
		w := httptest.NewRecorder()
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		engine.ServeHTTP(w, req)
		if out != nil && w.Code < 300 {
			if err := json.Unmarshal(w.Body.Bytes(), out); err != nil {
				t.Fatalf("%s %s: decode %s: %v", method, path, w.Body.String(), err)
			}
		}
		return w.Code
	}
	tripPath := "/api/v0/albums/" + strconv.FormatInt(trip.Album.ID, 10)
	dayPath := "/api/v0/albums/" + strconv.FormatInt(day.Album.ID, 10)
	counts := func() map[string]int64 {
		t.Helper()
		var albums []v0_albums.AlbumJSON
		do(http.MethodGet, "/api/v0/albums", "", &albums)
		got := map[string]int64{}
		for _, a := range albums {
			got[a.Name] = a.ItemCount
		}
		return got
	}
	items := func() []string {
		t.Helper()
		var list []v0_albums.AlbumItemJSON
		do(http.MethodGet, tripPath+"/items", "", &list)
		paths := make([]string, 0, len(list))
		for _, item := range list {
			paths = append(paths, item.RelPath)
		}
		return paths
	}

	if got := counts(); got["trip"] != 2 || got["day1"] != 1 {
		t.Errorf("admin counts = %v, want trip 2 and day1 1", got)
	}
	if got := items(); len(got) != 2 {
		t.Errorf("admin items = %v, want 2", got)
	}

	principal = accessutil.Principal{UserID: user.ID}
	if err := q.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		RelPath: "shared",
		UserID:  sql.NullInt64{Int64: user.ID, Valid: true},
		Level:   accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}

	if got := counts(); got["trip"] != 1 || got["day1"] != 0 {
		t.Errorf("user counts = %v, want trip 1 and day1 0", got)
	}
	var album v0_albums.AlbumJSON
	do(http.MethodGet, tripPath, "", &album)
	if album.ItemCount != 1 || len(album.Children) != 1 || album.Children[0].ItemCount != 0 {
		t.Errorf("user get album = count %d, children %+v, want 1 and one child with 0", album.ItemCount, album.Children)
	}
	if got := items(); len(got) != 1 || got[0] != "shared/a.jpg" {
		t.Errorf("user items = %v, want [shared/a.jpg]", got)
	}

	if code := do(http.MethodPost, tripPath+"/items", `{"relPath":"private/x.jpg"}`, nil); code != http.StatusNotFound {
		t.Errorf("add an unreadable photo = %d, want 404", code)
	}
	if code := do(http.MethodPost, tripPath+"/items", `{"relPath":"shared/new.jpg"}`, nil); code != http.StatusCreated {
		t.Errorf("add a readable photo = %d, want 201", code)
	}

	var renamed v0_albums.AlbumJSON
	if code := do(http.MethodPatch, tripPath+"/rename", `{"name":"trip2"}`, &renamed); code != http.StatusOK || renamed.ItemCount != 2 {
		t.Errorf("rename = %d with count %d, want 200 and 2", code, renamed.ItemCount)
	}
	var moved v0_albums.AlbumJSON
	if code := do(http.MethodPatch, dayPath+"/move", `{"parentId":null}`, &moved); code != http.StatusOK || moved.ItemCount != 0 {
		t.Errorf("move = %d with count %d, want 200 and 0", code, moved.ItemCount)
	}
}
