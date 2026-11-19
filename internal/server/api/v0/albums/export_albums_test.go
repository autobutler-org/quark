package v0_albums_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_albums "github.com/autobutler-org/quark/internal/server/api/v0/albums"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumexportutil"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// TestExportAlbums queues an export of an album holding a photo that is gone,
// runs it, and reads back a summary that names the missing photo, while the
// job reports failure rather than success (#3501).
func TestExportAlbums(t *testing.T) {
	ctx := context.Background()
	database := dbtest.NewDB(t)
	q := database.Queries
	user, err := q.CreateUser(ctx, db.CreateUserParams{Username: "grandma", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	if err := q.SetUserAdmin(ctx, db.SetUserAdminParams{Username: user.Username, IsAdmin: 1}); err != nil {
		t.Fatal(err)
	}
	album, err := albumutil.CreateAlbum(ctx, albumutil.CreateAlbumParams{Queries: q, UserID: user.ID, Name: "Holiday"})
	if err != nil {
		t.Fatal(err)
	}
	internal := vfs.NewMemVFS(vfs.FilesNamespace(""))
	if err := internal.Write(ctx, "beach.jpg", strings.NewReader("beach"), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"beach.jpg", "gone.jpg"} {
		if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.Album.ID, RelPath: p}); err != nil {
			t.Fatal(err)
		}
	}
	usb := vfs.NewMemVFS(vfs.FilesNamespace("USB-1"))
	reg := vfs.NewRegistry()
	for serial, fsys := range map[string]vfs.VFS{"": internal, "USB-1": usb} {
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database})
	queue.Register(jobutil.RegisterParams{Kind: albumexportutil.Kind, Handler: albumexportutil.NewHandler(albumexportutil.NewHandlerParams{
		Database: database, Registry: reg,
	})})
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(database).WithJobQueue(queue).WithEventBus(eventbus.New())

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	principal := accessutil.Principal{UserID: user.ID, IsAdmin: true}
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_albums.NewRouter())
	serve := func(method, url, body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(method, url, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		engine.ServeHTTP(w, req)
		return w
	}

	for body, want := range map[string]int{
		`{"deviceSerial":"USB-1"}`:                                     http.StatusBadRequest,
		`{"albumIds":[999],"deviceSerial":"USB-1"}`:                    http.StatusNotFound,
		`{"library":true,"deviceSerial":"USB-1","folder":"not/there"}`: http.StatusNotFound,
	} {
		if w := serve(http.MethodPost, "/api/v0/albums/exports", body); w.Code != want {
			t.Errorf("export %s = %d %s, want %d", body, w.Code, w.Body.String(), want)
		}
	}

	w := serve(http.MethodPost, "/api/v0/albums/exports", `{"albumIds":[`+strconv.FormatInt(album.Album.ID, 10)+`],"deviceSerial":"USB-1"}`)
	if w.Code != http.StatusAccepted {
		t.Fatalf("export = %d %s, want 202", w.Code, w.Body.String())
	}
	var queued v0_albums.AlbumExportJSON
	if err := json.Unmarshal(w.Body.Bytes(), &queued); err != nil {
		t.Fatal(err)
	}
	if queued.DeviceSerial != "USB-1" || queued.RelPath != "Holiday" {
		t.Fatalf("queued = %+v", queued)
	}

	runCtx, stop := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() { defer close(done); queue.Run(runCtx) }()
	t.Cleanup(func() { stop(); <-done })
	deadline := time.Now().Add(10 * time.Second)
	for {
		got, err := queue.Get(ctx, jobutil.GetParams{ID: queued.JobID})
		if err != nil {
			t.Fatal(err)
		}
		if got.Job.Status == jobutil.StatusFailed {
			break
		}
		if got.Job.Status == jobutil.StatusCompleted || time.Now().After(deadline) {
			t.Fatalf("job = %+v, want it to fail as a partial export", got.Job)
		}
		time.Sleep(20 * time.Millisecond)
	}

	w = serve(http.MethodGet, "/api/v0/albums/exports/"+strconv.FormatInt(queued.JobID, 10), "")
	if w.Code != http.StatusOK {
		t.Fatalf("summary = %d %s", w.Code, w.Body.String())
	}
	var summary v0_albums.AlbumExportSummaryJSON
	if err := json.Unmarshal(w.Body.Bytes(), &summary); err != nil {
		t.Fatal(err)
	}
	if summary.Status != "failed" || summary.Copied != 1 || len(summary.Failures) != 1 || summary.Failures[0].Name != "gone.jpg" {
		t.Fatalf("summary = %+v, want one copied and gone.jpg failed", summary)
	}
	if w := serve(http.MethodGet, "/api/v0/albums/exports/123456", ""); w.Code != http.StatusNotFound {
		t.Errorf("unknown export = %d, want 404", w.Code)
	}
}
