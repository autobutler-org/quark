package v0_versions_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	v0_versions "github.com/autobutler-org/quark/internal/server/api/v0/versions"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/trashutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

type fakeDetector struct{ mountPoint string }

func (d fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Disk", MountPoint: d.mountPoint, IsInternal: true}}, nil
}

// harness is the versions and files routers over a real files directory, the
// production StorageService-backed VFS and a migrated database, acting as one
// signed-in user.
type harness struct {
	engine    *gin.Engine
	deps      deputil.Dependencies
	svc       *storageutil.StorageService
	filesDir  string
	database  *db.DatabaseSqlc
	userID    int64
	principal *accessutil.Principal
}

func newHarness(t *testing.T, admin bool) harness {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(fakeDetector{mountPoint: mountPoint})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewStorageServiceVFS(svc, "files")); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	principal := &accessutil.Principal{UserID: user.ID, IsAdmin: admin}
	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(registry).
		WithEventBus(eventbus.New()).
		WithDatabase(database)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *principal)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_versions.NewRouter())
	serverutil.RegisterRouterWithGroup(group, v0_files.NewRouter())
	return harness{
		engine: engine, deps: deps, svc: svc, filesDir: filesDir,
		database: database, userID: user.ID, principal: principal,
	}
}

func (h harness) grant(t *testing.T, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: accessutil.Canonical(rel),
		UserID:  sql.NullInt64{Int64: h.userID, Valid: true},
		Level:   level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

func (h harness) write(t *testing.T, rel, content string) {
	t.Helper()
	full := filepath.Join(h.filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func (h harness) read(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(h.filesDir, filepath.FromSlash(rel)))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func (h harness) do(method, target string, body any) *httptest.ResponseRecorder {
	var reader io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		reader = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, target, reader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

func q(p string) string { return "?path=" + url.QueryEscape(p) }

func (h harness) snapshot(t *testing.T, p, label string) v0_versions.SnapshotJSON {
	t.Helper()
	w := h.do(http.MethodPost, "/api/v0/versions", map[string]string{"path": p, "label": label})
	if w.Code != http.StatusOK {
		t.Fatalf("snapshot %s = %d: %s", p, w.Code, w.Body.String())
	}
	var res v0_versions.SnapshotJSON
	decode(t, w, &res)
	return res
}

func (h harness) list(t *testing.T, p string) []v0_versions.VersionJSON {
	t.Helper()
	w := h.do(http.MethodGet, "/api/v0/versions"+q(p), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list %s = %d: %s", p, w.Code, w.Body.String())
	}
	var res v0_versions.ListVersionsJSON
	decode(t, w, &res)
	return res.Versions
}

func decode(t *testing.T, w *httptest.ResponseRecorder, v any) {
	t.Helper()
	if err := json.Unmarshal(w.Body.Bytes(), v); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
}

func TestVersions_SnapshotListDownloadRestoreDelete(t *testing.T) {
	h := newHarness(t, false)
	h.grant(t, "docs", accessutil.Write)
	events, cancel := h.deps.EventBus().Subscribe("test")
	defer cancel()

	h.write(t, "docs/deck.qslide", "A")
	a := h.snapshot(t, "docs/deck.qslide", "First draft")
	if !a.Created || a.Version.Kind != fileversionutil.KindNamed || a.Version.AuthorID != h.userID {
		t.Fatalf("snapshot = %+v, want a created named version by the caller", a)
	}
	if again := h.snapshot(t, "docs/deck.qslide", "Same"); again.Created || again.Version.ID != a.Version.ID {
		t.Fatalf("identical snapshot = %+v, want the first back uncreated", again)
	}

	w := h.do(http.MethodGet, "/api/v0/versions/"+a.Version.ID+"/content"+q("docs/deck.qslide"), nil)
	if w.Code != http.StatusOK || w.Body.String() != "A" {
		t.Fatalf("content = %d %q, want 200 A", w.Code, w.Body.String())
	}
	if cd := w.Header().Get("Content-Disposition"); !strings.Contains(cd, "deck.qslide") {
		t.Errorf("Content-Disposition = %q, want the file's name", cd)
	}

	// Restore A over B, then restore the backup: a restore is undoable.
	h.write(t, "docs/deck.qslide", "B")
	w = h.do(http.MethodPost, "/api/v0/versions/"+a.Version.ID+"/restore"+q("docs/deck.qslide"), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("restore = %d: %s", w.Code, w.Body.String())
	}
	var restored v0_versions.RestoreJSON
	decode(t, w, &restored)
	if h.read(t, "docs/deck.qslide") != "A" || restored.Backup.Label != fileversionutil.BeforeRestoreLabel {
		t.Fatalf("after restore file=%q backup=%+v", h.read(t, "docs/deck.qslide"), restored.Backup)
	}
	waitFor(t, events, eventbus.EventUpload, "docs/deck.qslide")
	w = h.do(http.MethodPost, "/api/v0/versions/"+restored.Backup.ID+"/restore"+q("docs/deck.qslide"), nil)
	if w.Code != http.StatusOK || h.read(t, "docs/deck.qslide") != "B" {
		t.Fatalf("restore of the restore = %d, file %q; want 200 and B", w.Code, h.read(t, "docs/deck.qslide"))
	}

	versions := h.list(t, "docs/deck.qslide")
	if len(versions) != 3 {
		t.Fatalf("versions = %+v, want the named one and two restore backups", versions)
	}
	// Restore backups are auto: not deletable by hand. The named one is.
	if w := h.do(http.MethodDelete, "/api/v0/versions/"+restored.Backup.ID+q("docs/deck.qslide"), nil); w.Code != http.StatusBadRequest {
		t.Errorf("delete auto = %d, want 400", w.Code)
	}
	if w := h.do(http.MethodDelete, "/api/v0/versions/"+a.Version.ID+q("docs/deck.qslide"), nil); w.Code != http.StatusOK {
		t.Fatalf("delete named = %d: %s", w.Code, w.Body.String())
	}
	if w := h.do(http.MethodGet, "/api/v0/versions/"+a.Version.ID+"/content"+q("docs/deck.qslide"), nil); w.Code != http.StatusNotFound {
		t.Errorf("content of a deleted version = %d, want 404", w.Code)
	}
}

func TestVersions_AccessFollowsTheFile(t *testing.T) {
	h := newHarness(t, true)
	h.write(t, "shared/deck.qslide", "A")
	h.write(t, "private/deck.qslide", "P")
	v := h.snapshot(t, "shared/deck.qslide", "A")
	p := h.snapshot(t, "private/deck.qslide", "P")

	h.principal.IsAdmin = false
	h.grant(t, "shared", accessutil.Read)
	shared, private := q("shared/deck.qslide"), q("private/deck.qslide")
	for _, tc := range []struct {
		method, target string
		body           any
		want           int
	}{
		{http.MethodGet, "/api/v0/versions" + shared, nil, http.StatusOK},
		{http.MethodGet, "/api/v0/versions/" + v.Version.ID + "/content" + shared, nil, http.StatusOK},
		{http.MethodPost, "/api/v0/versions", map[string]string{"path": "shared/deck.qslide", "label": "x"}, http.StatusForbidden},
		{http.MethodPost, "/api/v0/versions/" + v.Version.ID + "/restore" + shared, nil, http.StatusForbidden},
		{http.MethodDelete, "/api/v0/versions/" + v.Version.ID + shared, nil, http.StatusForbidden},
		{http.MethodGet, "/api/v0/versions" + private, nil, http.StatusNotFound},
		{http.MethodGet, "/api/v0/versions/" + p.Version.ID + "/content" + private, nil, http.StatusNotFound},
		{http.MethodPost, "/api/v0/versions", map[string]string{"path": "private/deck.qslide", "label": "x"}, http.StatusNotFound},
		{http.MethodPost, "/api/v0/versions/" + p.Version.ID + "/restore" + private, nil, http.StatusNotFound},
		{http.MethodDelete, "/api/v0/versions/" + p.Version.ID + private, nil, http.StatusNotFound},
	} {
		if w := h.do(tc.method, tc.target, tc.body); w.Code != tc.want {
			t.Errorf("%s %s = %d, want %d: %s", tc.method, tc.target, w.Code, tc.want, w.Body.String())
		}
	}
	if h.read(t, "private/deck.qslide") != "P" || h.read(t, "shared/deck.qslide") != "A" {
		t.Error("a refused request changed a file")
	}
}

func TestVersions_HostileInputIsRefused(t *testing.T) {
	h := newHarness(t, true)
	h.write(t, "deck.qslide", "A")
	h.write(t, "secret.txt", "secret")
	h.snapshot(t, "deck.qslide", "A")

	encodedSlashes := strings.ReplaceAll("../../secret.txt", "/", "%2F")
	for _, tc := range []struct {
		method, target string
		want           int
	}{
		// An encoded slash splits the id into segments no route matches.
		{http.MethodGet, "/api/v0/versions/" + encodedSlashes + "/content" + q("deck.qslide"), http.StatusNotFound},
		{http.MethodPost, "/api/v0/versions/" + encodedSlashes + "/restore" + q("deck.qslide"), http.StatusNotFound},
		{http.MethodGet, "/api/v0/versions/../content" + q("deck.qslide"), http.StatusBadRequest},
		{http.MethodGet, "/api/v0/versions/index/content" + q("deck.qslide"), http.StatusBadRequest},
		{http.MethodDelete, "/api/v0/versions/%2e%2e" + q("deck.qslide"), http.StatusBadRequest},
		{http.MethodGet, "/api/v0/versions" + q(""), http.StatusBadRequest},
		{http.MethodGet, "/api/v0/versions" + q(".trash/deck.qslide"), http.StatusBadRequest},
		{http.MethodGet, "/api/v0/versions" + q(storageutil.VersionsDirName+"/deck.qslide/index.json"), http.StatusBadRequest},
		{http.MethodGet, "/api/v0/versions/20261005T101530Z-3f9a0c1d/content" + q("../../../etc/passwd"), http.StatusNotFound},
	} {
		w := h.do(tc.method, tc.target, nil)
		if w.Code != tc.want {
			t.Errorf("%s %s = %d, want %d: %s", tc.method, tc.target, w.Code, tc.want, w.Body.String())
		}
		if strings.Contains(w.Body.String(), "secret") {
			t.Errorf("%s %s leaked another file", tc.method, tc.target)
		}
	}
	if w := h.do(http.MethodPost, "/api/v0/versions", map[string]string{"path": "deck.qslide"}); w.Code != http.StatusBadRequest {
		t.Errorf("named snapshot without a label = %d, want 400", w.Code)
	}
	if w := h.do(http.MethodPost, "/api/v0/versions", map[string]string{"path": "deck.qslide", "kind": "weird", "label": "x"}); w.Code != http.StatusBadRequest {
		t.Errorf("unknown kind = %d, want 400", w.Code)
	}
}

// The store stays out of the folder listing, follows a rename through the
// files API, survives the trash and goes once the trash is emptied.
func TestVersions_FollowTheFileThroughMoveTrashAndEmpty(t *testing.T) {
	h := newHarness(t, true)
	h.deps.FileVersions().Watch(fileversionutil.WatchParams{
		Bus: h.deps.EventBus(), Registry: h.deps.VFSRegistry(), Storage: h.svc,
	})
	h.write(t, "docs/deck.qslide", "A")
	v := h.snapshot(t, "docs/deck.qslide", "A")

	w := h.do(http.MethodGet, "/api/v0/files?rootDir=docs", nil)
	if w.Code != http.StatusOK || strings.Contains(w.Body.String(), storageutil.VersionsDirName) {
		t.Fatalf("listing = %d %s, want the store hidden", w.Code, w.Body.String())
	}

	w = h.do(http.MethodPut, "/api/v0/files", map[string]string{
		"oldFilePath": "docs/deck.qslide", "newFilePath": "archive/renamed.qslide",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("move = %d: %s", w.Code, w.Body.String())
	}
	eventually(t, "the history follows the rename", func() bool {
		versions := h.list(t, "archive/renamed.qslide")
		return len(versions) == 1 && versions[0].ID == v.Version.ID
	})
	if versions := h.list(t, "docs/deck.qslide"); len(versions) != 0 {
		t.Errorf("history still at the old path: %+v", versions)
	}

	w = h.do(http.MethodDelete, "/api/v0/files?filePaths="+url.QueryEscape("archive/renamed.qslide"), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("delete = %d: %s", w.Code, w.Body.String())
	}
	// The delete publishes from a goroutine; give the watcher every event
	// before checking the history was kept.
	time.Sleep(100 * time.Millisecond)
	if versions := h.list(t, "archive/renamed.qslide"); len(versions) != 1 {
		t.Fatalf("trashing the file dropped its history: %+v", versions)
	}

	if _, err := trashutil.Empty(trashutil.EmptyParams{
		Device:   trashutil.Device{Registry: h.deps.VFSRegistry()},
		EventBus: h.deps.EventBus(),
	}); err != nil {
		t.Fatal(err)
	}
	eventually(t, "the history goes with the emptied trash", func() bool {
		_, err := os.Stat(filepath.Join(h.filesDir, "archive", storageutil.VersionsDirName))
		return os.IsNotExist(err)
	})
}

func waitFor(t *testing.T, events <-chan eventbus.Event, kind eventbus.EventKind, p string) {
	t.Helper()
	timeout := time.After(2 * time.Second)
	for {
		select {
		case evt := <-events:
			if evt.Kind == kind && evt.Path == p {
				return
			}
		case <-timeout:
			t.Fatalf("no %s event for %s", kind, p)
		}
	}
}

func eventually(t *testing.T, what string, ok func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !ok() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(10 * time.Millisecond)
	}
}
