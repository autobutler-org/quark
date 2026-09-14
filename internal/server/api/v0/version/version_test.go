package v0_version_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	v0_version "github.com/autobutler-org/quark/internal/server/api/v0/version"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
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

// TestGetInstalledVersion_ReturnsOK verifies GET /version returns 200 with
// the expected fields populated.
func TestGetInstalledVersion_ReturnsOK(t *testing.T) {
	engine := newVersionEngine(t)

	w := doVersionReq(engine, http.MethodGet, "/api/v0/version", "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /version returned %d: %s", w.Code, w.Body.String())
	}
	var v v0_version.VersionJSON
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	// In test builds versionutil falls back to "NOSEMVER" — verify the field
	// exists and is a non-empty string.
	if v.Semver == "" {
		t.Error("Semver field is empty")
	}
	if v.GoVersion == "" {
		t.Error("GoVersion field is empty")
	}
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

// TestGetSbom_ReturnsOK verifies GET /sbom returns 200 with goVersion and
// a dependencies array.
func TestGetSbom_ReturnsOK(t *testing.T) {
	engine := newVersionEngine(t)

	w := doVersionReq(engine, http.MethodGet, "/api/v0/sbom", "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /sbom returned %d: %s", w.Code, w.Body.String())
	}
	var s v0_version.SbomJSON
	if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
		t.Fatalf("unmarshal SbomJSON: %v\nbody: %s", err, w.Body.String())
	}
	if s.GoVersion == "" {
		t.Error("SbomJSON.GoVersion is empty")
	}
	// The test binary always has at least one module (itself).
	if s.Dependencies == nil {
		t.Error("SbomJSON.Dependencies is nil")
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
