package v0_storage_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	v0_storage "github.com/autobutler-org/quark/internal/server/api/v0/storage"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

const backupSerial = "BACKUP-1"

// newVerifyEngine serves the admin storage routes over a registry holding the
// internal drive and, when attached, the backup drive.
func newVerifyEngine(t *testing.T, backupDrive vfs.VFS) *gin.Engine {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
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
	deps := deputil.NewDependencies().WithVFSRegistry(reg)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_storage.NewAdminRouter())
	return engine
}

func verify(engine *gin.Engine, serial string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v0/storage/devices/snapshot-backup/verify",
		strings.NewReader(`{"deviceSerial":"`+serial+`","full":true}`))
	req.Header.Set("Content-Type", "application/json")
	engine.ServeHTTP(w, req)
	return w
}

// The backup is read through the device's namespace.
func TestVerifySnapshotBackup_ReadsTheDeviceNamespace(t *testing.T) {
	drive := vfs.NewMemVFS(vfs.FilesNamespace(backupSerial))
	ctx := t.Context()
	if err := drive.Write(ctx, "internal/a.txt", strings.NewReader("aaa"), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	m, err := backup.GenerateManifest(ctx, drive)
	if err != nil {
		t.Fatal(err)
	}
	if err := backup.WriteManifest(ctx, m, drive); err != nil {
		t.Fatal(err)
	}

	w := verify(newVerifyEngine(t, drive), backupSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("verify = %d %s, want 200", w.Code, w.Body.String())
	}
	var result backup.VerifyResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.OK != 1 {
		t.Errorf("verify = %s, want 1 OK", w.Body.String())
	}
}

// A drive that is not plugged in has no namespace: 404, never the internal
// drive's tree.
func TestVerifySnapshotBackup_UnattachedDeviceIsNotFound(t *testing.T) {
	if w := verify(newVerifyEngine(t, nil), backupSerial); w.Code != http.StatusNotFound {
		t.Errorf("verify on an unplugged drive = %d %s, want 404", w.Code, w.Body.String())
	}
}

// A drive with no manifest has nothing to verify against: 400, as before.
func TestVerifySnapshotBackup_NoManifestIsBadRequest(t *testing.T) {
	drive := vfs.NewMemVFS(vfs.FilesNamespace(backupSerial))
	if w := verify(newVerifyEngine(t, drive), backupSerial); w.Code != http.StatusBadRequest {
		t.Errorf("verify without a manifest = %d %s, want 400", w.Code, w.Body.String())
	}
}
