package v0_storage_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_storage "github.com/autobutler-org/quark/internal/server/api/v0/storage"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// newRestoreFilesEngine serves the admin storage routes over a backup drive
// holding a snapshot of built-in storage and of a drive that is gone.
func newRestoreFilesEngine(t *testing.T, role string) *gin.Engine {
	t.Helper()
	database := dbtest.NewDB(t)
	if err := database.Queries.UpsertDeviceRole(context.Background(),
		db.UpsertDeviceRoleParams{DeviceSerial: backupSerial, Role: role}); err != nil {
		t.Fatal(err)
	}
	drive := vfs.NewMemVFS(vfs.FilesNamespace(backupSerial))
	ctx := context.Background()
	for _, p := range []string{"internal/a.txt", "Gone_GONE1234/b.txt"} {
		if err := drive.MkdirAll(ctx, p[:strings.Index(p, "/")]); err != nil {
			t.Fatal(err)
		}
		if err := drive.Write(ctx, p, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	reg := vfs.NewRegistry()
	for serial, fsys := range map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace("")), backupSerial: drive} {
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database})
	queue.Register(jobutil.RegisterParams{Kind: backup.RestoreKind, Handler: backup.NewRestoreHandler(backup.NewRestoreHandlerParams{Registry: reg})})
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(database).WithJobQueue(queue)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_storage.NewAdminRouter())
	return engine
}

func restoreFiles(engine *gin.Engine, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v0/storage/devices/snapshot-backup/restore-files", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	engine.ServeHTTP(w, req)
	return w
}

func TestRestoreSnapshotFiles_QueuesTheRestore(t *testing.T) {
	engine := newRestoreFilesEngine(t, "snapshot-backup")
	w := restoreFiles(engine, `{"deviceSerial":"`+backupSerial+`"}`)
	if w.Code != http.StatusAccepted {
		t.Fatalf("restore = %d %s, want 202", w.Code, w.Body.String())
	}
	var result backup.StartRestoreFilesResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.JobID == "" || len(result.Folders) != 1 || result.Folders[0].Folder != "internal" ||
		strings.Join(result.Missing, ",") != "Gone_GONE1234" {
		t.Errorf("result = %+v, want built-in queued and the gone drive missing", result)
	}

	w = restoreFiles(engine, `{"deviceSerial":"`+backupSerial+`","missingToBuiltIn":true}`)
	if w.Code != http.StatusAccepted || !strings.Contains(w.Body.String(), `"toBuiltIn":true`) {
		t.Errorf("restore to built-in = %d %s, want 202 with the gone drive going to built-in", w.Code, w.Body.String())
	}
}

func TestRestoreSnapshotFiles_Refusals(t *testing.T) {
	for _, tc := range []struct {
		name, role, body string
		want             int
	}{
		{"no serial", "snapshot-backup", `{}`, http.StatusBadRequest},
		{"not the snapshot drive", "default-storage", `{"deviceSerial":"` + backupSerial + `"}`, http.StatusBadRequest},
		{"drive not attached", "snapshot-backup", `{"deviceSerial":"NOPE"}`, http.StatusBadRequest},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if w := restoreFiles(newRestoreFilesEngine(t, tc.role), tc.body); w.Code != tc.want {
				t.Errorf("restore = %d %s, want %d", w.Code, w.Body.String(), tc.want)
			}
		})
	}
}
