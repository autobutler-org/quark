package v0_albums_test

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_albums "github.com/autobutler-org/quark/internal/server/api/v0/albums"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// TestAlbums_ConcurrentClientsSurviveCanceledNeighbors is the short CI smoke
// for concurrent load (#2516, #2507): authenticated clients list albums side by
// side while others give up on their requests part way through, and no client
// that waited for its answer may get anything but a 200.
//
// It runs on the database connection the server runs on, db.ConnectToDatabase,
// not dbtest's pool. Every request shares that one connection, and a canceled
// request used to interrupt it for everyone: the session lookup failed and
// requireAuth answered 401 to valid sessions (#2743). A cancellation has to
// land inside another request's statement for that to show, which a few
// seconds of HTTP cannot promise, so this is a smoke rather than that bug's
// regression test; TestSharedQueries_CanceledQueryDoesNotInterruptOthers in
// internal/db is.
func TestAlbums_ConcurrentClientsSurviveCanceledNeighbors(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	database, err := db.ConnectToDatabase()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { database.Db.Close() })
	ctx := context.Background()
	setup, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: filesDir, Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret})
	if err != nil {
		t.Fatal(err)
	}
	admin, err := database.Queries.GetUserByUsername(ctx, "admin")
	if err != nil {
		t.Fatal(err)
	}
	// Enough rows that a listing is still running when its client gives up.
	for i := range 300 {
		if _, err := albumutil.CreateAlbum(ctx, albumutil.CreateAlbumParams{UserID: admin.ID, Queries: database.Queries, Name: fmt.Sprintf("album-%d", i)}); err != nil {
			t.Fatal(err)
		}
	}

	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	middleware.Use(engine, deps)
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_albums.NewRouter())
	// Each request leaves a connected-device record running behind it. Once
	// the server has closed, wait for those before the database closes and
	// HOME is removed, or a late write races the TempDir cleanup (#2772).
	t.Cleanup(deps.Background().Wait)
	server := httptest.NewServer(engine)
	t.Cleanup(server.Close)

	list := func(ctx context.Context) (int, error) {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, server.URL+"/api/v0/albums", nil)
		if err != nil {
			return 0, err
		}
		req.Header.Set("Authorization", "Bearer "+setup.SessionToken)
		resp, err := server.Client().Do(req)
		if err != nil {
			return 0, err
		}
		defer resp.Body.Close()
		_, err = io.Copy(io.Discard, resp.Body)
		return resp.StatusCode, err
	}

	const rounds, clients = 10, 16
	var mu sync.Mutex
	statuses := map[int]int{}
	for round := range rounds {
		var wg sync.WaitGroup
		for client := range clients {
			wg.Go(func() {
				// Every other client hangs up a little way into its request.
				if client%2 == 0 {
					ctx, cancel := context.WithTimeout(context.Background(), time.Duration(client*round%5000+100)*time.Microsecond)
					defer cancel()
					_, _ = list(ctx)
					return
				}
				status, err := list(context.Background())
				if err != nil {
					t.Errorf("round %d: list albums: %v", round, err)
					return
				}
				mu.Lock()
				statuses[status]++
				mu.Unlock()
			})
		}
		wg.Wait()
	}
	if want := rounds * clients / 2; statuses[http.StatusOK] != want {
		t.Errorf("statuses for clients that waited = %v, want %d of 200", statuses, want)
	}
}
