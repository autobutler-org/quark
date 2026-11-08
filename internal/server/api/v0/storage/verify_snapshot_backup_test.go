package v0_storage_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path"
	"strings"
	"testing"
	"time"

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

// testRun is the run folder the tests put on a backup drive.
const testRun = "2026-11-07 21.57"

// putRun puts a complete run named folder on fsys, holding files keyed by
// their path in the run, with a manifest that names drives.
func putRun(t *testing.T, fsys vfs.VFS, folder string, drives []backup.ManifestDrive, files map[string]string) {
	t.Helper()
	ctx := context.Background()
	dir := path.Join(backup.BackupsDir, folder)
	if err := fsys.MkdirAll(ctx, dir); err != nil {
		t.Fatal(err)
	}
	for p, content := range files {
		full := path.Join(dir, p)
		if err := fsys.MkdirAll(ctx, path.Dir(full)); err != nil {
			t.Fatal(err)
		}
		if err := fsys.Write(ctx, full, strings.NewReader(content), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	m, err := backup.GenerateManifest(ctx, fsys, dir)
	if err != nil {
		t.Fatal(err)
	}
	m.CompletedAt, m.Drives = time.Now(), drives
	if err := backup.WriteManifest(ctx, m, fsys, dir); err != nil {
		t.Fatal(err)
	}
}

func verify(engine *gin.Engine, serial string) *httptest.ResponseRecorder {
	return verifyBody(engine, `{"deviceSerial":"`+serial+`","full":true}`)
}

func verifyBody(engine *gin.Engine, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v0/storage/devices/snapshot-backup/verify",
		strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	engine.ServeHTTP(w, req)
	return w
}

// The backup is read through the device's namespace, from the newest run
// unless the body names one.
func TestVerifySnapshotBackup_ReadsTheDeviceNamespace(t *testing.T) {
	drive := vfs.NewMemVFS(vfs.FilesNamespace(backupSerial))
	putRun(t, drive, testRun, nil, map[string]string{"Built-in storage/a.txt": "aaa"})
	engine := newVerifyEngine(t, drive)

	w := verify(engine, backupSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("verify = %d %s, want 200", w.Code, w.Body.String())
	}
	var result backup.VerifyResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.OK != 1 || result.Run != testRun {
		t.Errorf("verify = %s, want 1 OK in run %s", w.Body.String(), testRun)
	}

	body := `{"deviceSerial":"` + backupSerial + `","run":"` + testRun + `"}`
	if w := verifyBody(engine, body); w.Code != http.StatusOK {
		t.Errorf("verify of run %s = %d %s, want 200", testRun, w.Code, w.Body.String())
	}
	for _, run := range []string{"nope", "../" + testRun, "." + testRun + ".partial"} {
		body := `{"deviceSerial":"` + backupSerial + `","run":"` + run + `"}`
		if w := verifyBody(engine, body); w.Code != http.StatusNotFound {
			t.Errorf("verify of run %q = %d %s, want 404", run, w.Code, w.Body.String())
		}
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
	w := verify(newVerifyEngine(t, drive), backupSerial)
	if w.Code != http.StatusBadRequest {
		t.Errorf("verify without a manifest = %d %s, want 400", w.Code, w.Body.String())
	}
	body := w.Body.String()
	if strings.Contains(body, "vfs: not found") || !strings.Contains(body, "Back Up") {
		t.Errorf("verify without a manifest body = %s, want it to name Back Up and not the vfs error", body)
	}
}

// Built-in storage is the drive with serial "": it reaches the verify, which
// finds no manifest there.
func TestVerifySnapshotBackup_BuiltInStorage(t *testing.T) {
	w := verify(newVerifyEngine(t, nil), "")
	if w.Code != http.StatusBadRequest || !strings.Contains(w.Body.String(), "Back Up") {
		t.Errorf("verify on built-in storage = %d %s, want 400 naming Back Up", w.Code, w.Body.String())
	}
}
