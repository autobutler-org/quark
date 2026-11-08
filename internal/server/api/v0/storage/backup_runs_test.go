package v0_storage_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_storage "github.com/autobutler-org/quark/internal/server/api/v0/storage"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// slashVFS ends every folder's name in a listing with "/", as the files
// namespace of a real drive does (#4043).
type slashVFS struct{ vfs.VFS }

func (s slashVFS) List(ctx context.Context, p string, filter *vfs.ListFilter) ([]vfs.FileInfo, error) {
	entries, err := s.VFS.List(ctx, p, filter)
	for i := range entries {
		if entries[i].IsDir {
			entries[i].Name += "/"
		}
	}
	return entries, err
}

// runsEngine serves the admin storage routes over a database where the backup
// drive and built-in storage hold the snapshot-backup role, built-in storage,
// and the backup drive when it is attached.
type runsEngine struct {
	*gin.Engine
	database *db.DatabaseSqlc
	events   <-chan eventbus.Event
}

func newRunsEngine(t *testing.T, backupDrive vfs.VFS) runsEngine {
	t.Helper()
	database := dbtest.NewDB(t)
	for _, serial := range []string{"", backupSerial, "GONE"} {
		if err := database.Queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{DeviceSerial: serial, Role: "snapshot-backup"}); err != nil {
			t.Fatal(err)
		}
	}
	reg := vfs.NewRegistry()
	namespaces := map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace(""))}
	if backupDrive != nil {
		namespaces[backupSerial] = backupDrive
	}
	for serial, fsys := range namespaces {
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	t.Cleanup(unsubscribe)
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(database).WithEventBus(bus)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_storage.NewAdminRouter())
	return runsEngine{Engine: engine, database: database, events: events}
}

func (e runsEngine) list(query string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	e.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/storage/devices/snapshot-backup/runs"+query, nil))
	return w
}

func (e runsEngine) delete(serial, run string) *httptest.ResponseRecorder {
	body, _ := json.Marshal(map[string]string{"deviceSerial": serial, "run": run})
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodDelete, "/api/v0/storage/devices/snapshot-backup/runs", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	e.ServeHTTP(w, req)
	return w
}

// twoRunDrive holds an older and a newer complete run and a partial one.
func twoRunDrive(t *testing.T) *vfs.MemVFS {
	t.Helper()
	drive := vfs.NewMemVFS(vfs.FilesNamespace(backupSerial))
	putRun(t, drive, "2026-11-01 09.00", []backup.ManifestDrive{{Folder: "Built-in storage", Name: "Pi"}},
		map[string]string{"Built-in storage/a.txt": "aaa"})
	putRun(t, drive, "2026-11-02 09.00", []backup.ManifestDrive{{Folder: "Built-in storage", Name: "Pi"}},
		map[string]string{"Built-in storage/a.txt": "aaaa"})
	putRun(t, drive, ".2026-11-03 09.00.partial", nil, map[string]string{"x": "x"})
	return drive
}

// A drive's runs come newest first with their sizes and drives; a partial
// run is not listed, and a drive with none lists an empty array.
func TestListBackupRuns(t *testing.T) {
	e := newRunsEngine(t, slashVFS{twoRunDrive(t)})
	w := e.list("?deviceSerial=" + backupSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("list = %d %s, want 200", w.Code, w.Body.String())
	}
	var result backup.ListDriveRunsResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if len(result.Runs) != 2 || result.Runs[0].Folder != "2026-11-02 09.00" || result.Runs[1].Folder != "2026-11-01 09.00" {
		t.Fatalf("runs = %s, want the two complete runs, newest first", w.Body.String())
	}
	if result.Runs[0].SizeBytes != 4 || len(result.Runs[0].Drives) != 1 || result.Runs[0].Drives[0].Name != "Pi" {
		t.Errorf("newest run = %+v, want 4 bytes of Pi", result.Runs[0])
	}

	for _, query := range []string{"?deviceSerial=", ""} {
		if w := e.list(query); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"runs":[]`) {
			t.Errorf("list of built-in storage (%q) = %d %s, want 200 and no runs", query, w.Code, w.Body.String())
		}
	}
}

// A drive without the role is 400, and one that is not attached is 404.
func TestListBackupRuns_RoleAndAttachment(t *testing.T) {
	e := newRunsEngine(t, nil)
	if w := e.list("?deviceSerial=DATA"); w.Code != http.StatusBadRequest {
		t.Errorf("list on a drive without the role = %d %s, want 400", w.Code, w.Body.String())
	}
	if w := e.list("?deviceSerial=GONE"); w.Code != http.StatusNotFound {
		t.Errorf("list on an unplugged drive = %d %s, want 404", w.Code, w.Body.String())
	}
}

// Deleting a run removes its folder and publishes backup_deleted; the other
// run stays.
func TestDeleteBackupRun(t *testing.T) {
	drive := twoRunDrive(t)
	e := newRunsEngine(t, slashVFS{drive})
	if w := e.delete(backupSerial, "2026-11-01 09.00"); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"folder":"2026-11-01 09.00"`) {
		t.Fatalf("delete = %d %s, want 200 naming the run", w.Code, w.Body.String())
	}
	if _, err := drive.Stat(t.Context(), path.Join(backup.BackupsDir, "2026-11-01 09.00")); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("the run's folder is still there: %v", err)
	}
	if w := e.list("?deviceSerial=" + backupSerial); !strings.Contains(w.Body.String(), "2026-11-02 09.00") || strings.Contains(w.Body.String(), "2026-11-01 09.00") {
		t.Errorf("list after the delete = %s, want the newer run alone", w.Body.String())
	}
	select {
	case evt := <-e.events:
		if evt.Kind != eventbus.EventBackupDeleted {
			t.Errorf("event = %+v, want backup_deleted", evt)
		}
	case <-time.After(time.Second):
		t.Error("no event published")
	}
}

// Only a listed run is deleted: anything else is 404 and touches nothing.
func TestDeleteBackupRun_UnknownRunIsNotFound(t *testing.T) {
	drive := twoRunDrive(t)
	e := newRunsEngine(t, drive)
	for _, run := range []string{"", "nope", ".2026-11-03 09.00.partial", "../backups/2026-11-01 09.00", "..", "2026-11-01 09.00/Built-in storage"} {
		if w := e.delete(backupSerial, run); w.Code != http.StatusNotFound {
			t.Errorf("delete of %q = %d %s, want 404", run, w.Code, w.Body.String())
		}
	}
	if w := e.delete("GONE", "2026-11-01 09.00"); w.Code != http.StatusNotFound {
		t.Errorf("delete on an unplugged drive = %d %s, want 404", w.Code, w.Body.String())
	}
	if w := e.delete("DATA", "2026-11-01 09.00"); w.Code != http.StatusBadRequest {
		t.Errorf("delete on a drive without the role = %d %s, want 400", w.Code, w.Body.String())
	}
	if _, err := drive.Stat(t.Context(), path.Join(backup.BackupsDir, ".2026-11-03 09.00.partial")); err != nil {
		t.Errorf("the partial run was touched: %v", err)
	}
}

// A run is not deleted while a backup onto its drive is pending or running.
func TestDeleteBackupRun_ActiveBackupIsConflict(t *testing.T) {
	drive := twoRunDrive(t)
	e := newRunsEngine(t, drive)
	if _, err := e.database.Queries.CreateJob(t.Context(), db.CreateJobParams{
		Kind: backup.Kind, Name: "backup", Params: `{"targetDeviceSerial":"` + backupSerial + `"}`,
	}); err != nil {
		t.Fatal(err)
	}
	if w := e.delete(backupSerial, "2026-11-01 09.00"); w.Code != http.StatusConflict {
		t.Errorf("delete during a backup = %d %s, want 409", w.Code, w.Body.String())
	}
	if _, err := drive.Stat(t.Context(), path.Join(backup.BackupsDir, "2026-11-01 09.00")); err != nil {
		t.Errorf("a refused delete removed the run: %v", err)
	}
}
