package v0_version_test

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	v0_version "github.com/autobutler-org/quark/internal/server/api/v0/version"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/updateutil"

	"github.com/gin-gonic/gin"
)

func newVersionEngine(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_version.NewRouter())
	// routes.go mounts this one behind RequireAdmin.
	serverutil.RegisterRouterWithGroup(group, v0_version.NewAdminRouter())
	return engine
}

func doVersionReq(engine *gin.Engine, method, path string, body string) *httptest.ResponseRecorder {
	var r *strings.Reader
	if body != "" {
		r = strings.NewReader(body)
	} else {
		r = strings.NewReader("")
	}
	req := httptest.NewRequest(method, path, r)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestGetInstalledVersion_ResponseShape verifies the response contains the
// expected JSON keys.
func TestGetInstalledVersion_ResponseShape(t *testing.T) {
	engine := newVersionEngine(t)

	w := doVersionReq(engine, http.MethodGet, "/api/v0/version", "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /version returned %d", w.Code)
	}
	var raw map[string]any
	json.Unmarshal(w.Body.Bytes(), &raw)
	for _, field := range []string{"semver", "gitCommit", "goVersion", "buildDate"} {
		if _, ok := raw[field]; !ok {
			t.Errorf("response missing field %q", field)
		}
	}
}

// TestGetSbom_ResponseShape verifies the SBOM response has the expected
// top-level JSON structure.
func TestGetSbom_ResponseShape(t *testing.T) {
	engine := newVersionEngine(t)

	w := doVersionReq(engine, http.MethodGet, "/api/v0/sbom", "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /sbom returned %d", w.Code)
	}
	var raw map[string]any
	json.Unmarshal(w.Body.Bytes(), &raw)
	for _, field := range []string{"goVersion", "main", "dependencies"} {
		if _, ok := raw[field]; !ok {
			t.Errorf("SBOM response missing field %q", field)
		}
	}
}

// TestDoUpdate_MissingVersionReturns400 verifies POST /version/update without
// a version parameter returns 400.
func TestDoUpdate_MissingVersionReturns400(t *testing.T) {
	engine := newVersionEngine(t)

	w := doVersionReq(engine, http.MethodPost, "/api/v0/version/update", `{}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing version, got %d: %s", w.Code, w.Body.String())
	}
}

// TestDoUpdate_InvalidBodyReturns400 verifies POST /version/update with
// malformed JSON returns 400.
func TestDoUpdate_InvalidBodyReturns400(t *testing.T) {
	engine := newVersionEngine(t)

	w := doVersionReq(engine, http.MethodPost, "/api/v0/version/update", `{{{not json`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid JSON, got %d: %s", w.Code, w.Body.String())
	}
}

// TestDoUpdate_DockerInstallSchedulesOneRestart is the Docker install path
// (#3218): one POST writes the binary into QUARK_UPDATE_DIR and schedules one
// restart. A failed install can be tried again. A second POST while that
// restart is pending returns 409 and does not download the release again.
func TestDoUpdate_DockerInstallSchedulesOneRestart(t *testing.T) {
	archive := updateutil.ConstructArchiveName()
	if archive == "" {
		t.Skip("no release archive for this platform")
	}

	dir := t.TempDir()
	t.Setenv(updateutil.UpdateDirEnv, dir)

	const version = "v9.9.9"
	payload := []byte("quark-update-binary")
	body := gzipTar(t, "quark", payload)
	sum := sha256.Sum256(body)
	checksumName := fmt.Sprintf("quark_%s_checksums.txt", strings.TrimPrefix(version, "v"))

	var archiveDownloads atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/"+archive):
			if !strings.Contains(r.URL.Path, "/"+version+"/") {
				http.NotFound(w, r)
				return
			}
			archiveDownloads.Add(1)
			if _, err := w.Write(body); err != nil {
				t.Errorf("write archive: %v", err)
			}
		case strings.HasSuffix(r.URL.Path, "/"+checksumName):
			if _, err := fmt.Fprintf(w, "%x  %s\n", sum[:], archive); err != nil {
				t.Errorf("write checksums: %v", err)
			}
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)

	t.Cleanup(updateutil.AllowInsecureFetchForTest())

	source := updateutil.NewUpdateSource(updateutil.UpdateSourceKindGithub, "autobutler-org", "quark")
	source.BaseURLOverride = server.URL
	t.Cleanup(updateutil.SetApplyUpdateForTest(func(_ *updateutil.UpdateSource, version string) error {
		return updateutil.Update(source, version)
	}))

	var restarts atomic.Int32
	t.Cleanup(updateutil.SetRestartExitForTest(func(int) { restarts.Add(1) }))

	engine := newVersionEngine(t)

	missing := doVersionReq(engine, http.MethodPost, "/api/v0/version/update", `{"version":"v0.0.1"}`)
	if missing.Code != http.StatusInternalServerError {
		t.Fatalf("missing release returned %d, want 500: %s", missing.Code, missing.Body.String())
	}
	if archiveDownloads.Load() != 0 {
		t.Fatalf("a missing release was counted as a download: %d", archiveDownloads.Load())
	}

	first := doVersionReq(engine, http.MethodPost, "/api/v0/version/update", `{"version":"`+version+`"}`)
	if first.Code != http.StatusOK {
		t.Fatalf("update returned %d, want 200: %s", first.Code, first.Body.String())
	}
	waitFor(t, func() bool { return restarts.Load() == 1 })
	if archiveDownloads.Load() != 1 {
		t.Fatalf("archive downloads = %d, want 1", archiveDownloads.Load())
	}
	installed, err := os.ReadFile(filepath.Join(dir, "quark"))
	if err != nil {
		t.Fatalf("read installed binary: %v", err)
	}
	if !bytes.Equal(installed, payload) {
		t.Fatalf("installed binary = %q, want %q", installed, payload)
	}

	second := doVersionReq(engine, http.MethodPost, "/api/v0/version/update", `{"version":"`+version+`"}`)
	if second.Code != http.StatusConflict {
		t.Fatalf("second update returned %d, want 409: %s", second.Code, second.Body.String())
	}
	if !strings.Contains(second.Body.String(), updateutil.ErrUpdateInProgress.Error()) {
		t.Fatalf("conflict body = %s", second.Body.String())
	}
	if archiveDownloads.Load() != 1 {
		t.Fatalf("second update downloaded again: %d archive fetches", archiveDownloads.Load())
	}
	if restarts.Load() != 1 {
		t.Fatalf("restarts = %d, want 1", restarts.Load())
	}
}

func gzipTar(t *testing.T, name string, content []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{
		Name:     name,
		Mode:     0o755,
		Size:     int64(len(content)),
		Typeflag: tar.TypeReg,
	}); err != nil {
		t.Fatalf("tar header: %v", err)
	}
	if _, err := tw.Write(content); err != nil {
		t.Fatalf("tar write: %v", err)
	}
	if err := tw.Close(); err != nil {
		t.Fatalf("tar close: %v", err)
	}
	if err := gz.Close(); err != nil {
		t.Fatalf("gzip close: %v", err)
	}
	return buf.Bytes()
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("timed out waiting for the scheduled restart")
}
