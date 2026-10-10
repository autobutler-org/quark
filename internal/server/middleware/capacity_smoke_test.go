package middleware_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// TestRequireAuth_ConcurrentSessionsSurviveDeviceWrites is the CI-sized smoke
// for #2507 (#2516): many requests on one valid session arrive at once, each
// leaving trackDevice's connected_devices write behind on another connection,
// and every one of them is a 200. A session read that loses to a write must
// wait for it, not come back as the 401 that signs the user out or as a 5xx.
// It is a hundred-odd requests, not a soak: the 1k-4k user load test stays
// with #2507 and test/performance.
func TestRequireAuth_ConcurrentSessionsSurviveDeviceWrites(t *testing.T) {
	sqlDB, queries := newMiddlewareTestDB(t)
	database := &db.DatabaseSqlc{Db: sqlDB, Queries: queries}
	result, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, Files: vfs.NewMemVFS("files"),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("SecurePass1!"), SaltSecret: dbtest.SaltSecret,
	})
	if err != nil {
		t.Fatalf("Setup: %v", err)
	}
	engine := newMiddlewareEngine(t, deputil.NewDependencies().WithDatabase(database))

	const workers, perWorker = 16, 8
	var wg sync.WaitGroup
	codes := make([]int, workers*perWorker)
	for i := range codes {
		if i%perWorker != 0 {
			continue
		}
		wg.Go(func() {
			for j := range perWorker {
				req := httptest.NewRequest(http.MethodGet, "/api/v0/protected", nil)
				req.Header.Set("Authorization", "Bearer "+result.SessionToken)
				// One peer per worker, so the writes are the returning-device
				// upsert almost every real request makes.
				req.Header.Set("User-Agent", "capacity-smoke-"+strconv.Itoa(i))
				codes[i+j] = doMiddlewareReq(engine, req).Code
			}
		})
	}
	wg.Wait()

	failed := map[int]int{}
	for _, code := range codes {
		if code != http.StatusOK {
			failed[code]++
		}
	}
	if len(failed) != 0 {
		t.Errorf("%d concurrent requests on a valid session: status → count of the ones that weren't 200: %v", len(codes), failed)
	}
}
