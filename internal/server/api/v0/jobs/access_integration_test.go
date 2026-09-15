package v0_jobs_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_jobs "github.com/autobutler-org/quark/internal/server/api/v0/jobs"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// internalDevice is the internal drive at "/", whose files directory is the one
// storageutil.GetFilesDir resolves under HOME.
type internalDevice struct{}

func (internalDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// accessHarness serves the jobs routes over a migrated database and a real
// files directory, acting as whoever principal names (#1979). Every job it
// runs fails with an error naming a host path.
type accessHarness struct {
	engine    *gin.Engine
	database  *db.DatabaseSqlc
	queue     *jobutil.Queue
	principal *accessutil.Principal
	bob       int64
	carol     int64
}

func newAccessHarness(t *testing.T) accessHarness {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{"shared", "private"} {
		if err := os.MkdirAll(filepath.Join(filesDir, dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	database := dbtest.NewDB(t)
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database})
	queue.Register(jobutil.RegisterParams{Kind: testKind, Handler: jobutil.Handler{
		Run: func(context.Context, json.RawMessage, func(float64)) error {
			return errors.New("ffmpeg: " + filesDir + "/shared/a.mkv: boom")
		},
	}})
	deps := deputil.NewDependencies().
		WithDatabase(database).
		WithStorageService(storageutil.NewStorageService(internalDevice{})).
		WithJobQueue(queue)
	principal := &accessutil.Principal{}

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_jobs.NewRouter())

	h := accessHarness{engine: engine, database: database, queue: queue, principal: principal}
	h.bob = h.createUser(t, "bob")
	h.carol = h.createUser(t, "carol")
	return h
}

func (h accessHarness) createUser(t *testing.T, username string) int64 {
	t.Helper()
	user, err := h.database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: username, PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	return user.ID
}

func (h accessHarness) grant(t *testing.T, userID int64, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: rel,
		UserID:  sql.NullInt64{Int64: userID, Valid: true},
		Level:   level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

// failedJob queues a job on rel for userID and waits for it to fail.
func (h accessHarness) failedJob(t *testing.T, userID int64, rel string) jobutil.Job {
	t.Helper()
	res, err := h.queue.Enqueue(context.Background(), jobutil.EnqueueParams{
		Kind:   testKind,
		Name:   rel,
		Params: map[string]string{"serial": "", "relPath": rel},
		UserID: userID,
	})
	if err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(testTimeout)
	for {
		got, err := h.queue.Get(context.Background(), jobutil.GetParams{ID: res.Job.ID})
		if err != nil {
			t.Fatal(err)
		}
		if got.Job.Status == jobutil.StatusFailed {
			return got.Job
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %s is %s, want failed", rel, got.Job.Status)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func (h accessHarness) do(principal accessutil.Principal, method, path string) *httptest.ResponseRecorder {
	*h.principal = principal
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(method, path, nil))
	return w
}

func TestJobAccess(t *testing.T) {
	h := newAccessHarness(t)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		h.queue.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})

	h.grant(t, h.bob, "shared", accessutil.Write)
	h.grant(t, h.carol, "shared", accessutil.Read)
	bobs := h.failedJob(t, h.bob, "shared/a.mkv")
	carols := h.failedJob(t, h.carol, "shared/b.mkv")
	unowned := h.failedJob(t, 0, "shared/c.mkv")
	bobsPrivate := h.failedJob(t, h.bob, "private/d.mkv")
	bob := accessutil.Principal{UserID: h.bob}
	carol := accessutil.Principal{UserID: h.carol}
	admin := accessutil.System

	t.Run("lists", func(t *testing.T) {
		for _, tc := range []struct {
			name      string
			principal accessutil.Principal
			want      []int64
			errors    bool
		}{
			{"bob sees only his readable job", bob, []int64{bobs.ID}, false},
			{"carol sees only hers, not bob's in a folder shared with her", carol, []int64{carols.ID}, false},
			{"an admin sees every job and its error", admin, []int64{bobsPrivate.ID, unowned.ID, carols.ID, bobs.ID}, true},
			{"nobody sees nothing", accessutil.Principal{}, []int64{}, false},
		} {
			w := h.do(tc.principal, http.MethodGet, "/api/v0/jobs?kind="+testKind)
			jobs := decode[[]jobutil.Job](t, w)
			ids := make([]int64, 0, len(jobs))
			for _, job := range jobs {
				ids = append(ids, job.ID)
				if (job.Error != "") != tc.errors {
					t.Errorf("%s: job %d error = %q, want shown %v", tc.name, job.ID, job.Error, tc.errors)
				}
			}
			if w.Code != http.StatusOK || fmt.Sprint(ids) != fmt.Sprint(tc.want) {
				t.Errorf("%s: GET /jobs = %d %v, want 200 %v", tc.name, w.Code, ids, tc.want)
			}
		}
	})

	t.Run("get, cancel and retry of a job the caller can't see", func(t *testing.T) {
		for _, tc := range []struct {
			principal accessutil.Principal
			method    string
			path      string
			want      int
		}{
			{bob, http.MethodGet, fmt.Sprintf("/api/v0/jobs/%d", bobs.ID), http.StatusOK},
			{bob, http.MethodGet, fmt.Sprintf("/api/v0/jobs/%d", carols.ID), http.StatusNotFound},
			{bob, http.MethodGet, fmt.Sprintf("/api/v0/jobs/%d", unowned.ID), http.StatusNotFound},
			{bob, http.MethodGet, fmt.Sprintf("/api/v0/jobs/%d", bobsPrivate.ID), http.StatusNotFound},
			{bob, http.MethodGet, "/api/v0/jobs/9999", http.StatusNotFound},
			{carol, http.MethodGet, fmt.Sprintf("/api/v0/jobs/%d", bobs.ID), http.StatusNotFound},
			{bob, http.MethodDelete, fmt.Sprintf("/api/v0/jobs/%d", carols.ID), http.StatusNotFound},
			{bob, http.MethodDelete, fmt.Sprintf("/api/v0/jobs/%d", bobs.ID), http.StatusConflict},
			{bob, http.MethodPost, fmt.Sprintf("/api/v0/jobs/%d/retry", carols.ID), http.StatusNotFound},
			{bob, http.MethodPost, fmt.Sprintf("/api/v0/jobs/%d/retry", unowned.ID), http.StatusNotFound},
			{bob, http.MethodPost, fmt.Sprintf("/api/v0/jobs/%d/retry", bobsPrivate.ID), http.StatusNotFound},
		} {
			if w := h.do(tc.principal, tc.method, tc.path); w.Code != tc.want {
				t.Errorf("%s %s as %d = %d, want %d: %s", tc.method, tc.path, tc.principal.UserID, w.Code, tc.want, w.Body.String())
			}
		}
		if got := decode[jobutil.Job](t, h.do(bob, http.MethodGet, fmt.Sprintf("/api/v0/jobs/%d", bobs.ID))); got.Error != "" {
			t.Errorf("bob's job error = %q, want it blank", got.Error)
		}
		if got := decode[jobutil.Job](t, h.do(admin, http.MethodGet, fmt.Sprintf("/api/v0/jobs/%d", unowned.ID))); got.Error == "" {
			t.Error("an admin's view of a job has no error")
		}
	})

	t.Run("retry needs the creator to still write the folder", func(t *testing.T) {
		retry := func(principal accessutil.Principal, job jobutil.Job) int {
			return h.do(principal, http.MethodPost, fmt.Sprintf("/api/v0/jobs/%d/retry", job.ID)).Code
		}
		h.grant(t, h.bob, "shared", accessutil.Read)
		if got := retry(bob, bobs); got != http.StatusForbidden {
			t.Errorf("bob's retry after losing write = %d, want 403", got)
		}
		if got := retry(admin, bobs); got != http.StatusForbidden {
			t.Errorf("an admin's retry of a job whose creator lost write = %d, want 403", got)
		}
		if _, err := h.database.Queries.SetUserStatus(context.Background(), db.SetUserStatusParams{
			ToStatus: authutil.StatusDisabled, Username: "carol", FromStatus: authutil.StatusActive,
		}); err != nil {
			t.Fatal(err)
		}
		if got := retry(admin, carols); got != http.StatusForbidden {
			t.Errorf("an admin's retry of a disabled account's job = %d, want 403", got)
		}

		h.grant(t, h.bob, "shared", accessutil.Write)
		if got := retry(bob, bobs); got != http.StatusAccepted {
			t.Errorf("bob's retry with write = %d, want 202", got)
		}
		if got := retry(admin, unowned); got != http.StatusAccepted {
			t.Errorf("an admin's retry of a job with no creator = %d, want 202", got)
		}
	})
}
