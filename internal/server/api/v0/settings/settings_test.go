package v0_settings_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	v0_settings "github.com/autobutler-org/quark/internal/server/api/v0/settings"
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// newSettingsEngine creates a gin engine with settings routes and an isolated
// temp settings file via settingsutil.ResetForTesting.
func newSettingsEngine(t *testing.T) *gin.Engine {
	t.Helper()
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_settings.NewRouter())
	return engine
}

// newSettingsEngineWithAdmin adds the admin routes, which routes.go mounts
// behind RequireAdmin, so they can be exercised directly.
func newSettingsEngineWithAdmin(t *testing.T) *gin.Engine {
	t.Helper()
	engine := newSettingsEngine(t)
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_settings.NewAdminRouter())
	return engine
}

func doSettingsReq(engine *gin.Engine, method, path string, body []byte) *httptest.ResponseRecorder {
	var reqBody *bytes.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	} else {
		reqBody = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, reqBody)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestSettingsRoot_NotServed pins the removal of the automatic updates
// setting (#2792): it was the only thing GET and POST /settings carried, and
// nothing read it, so neither router serves the bare path any more.
func TestSettingsRoot_NotServed(t *testing.T) {
	engine := newSettingsEngineWithAdmin(t)

	for _, method := range []string{http.MethodGet, http.MethodPost} {
		if w := doSettingsReq(engine, method, "/api/v0/settings", []byte(`{"autoUpdate":true}`)); w.Code != http.StatusNotFound {
			t.Errorf("%s /settings returned %d; want 404", method, w.Code)
		}
	}
}

// TestGetRemoteAccess_StaleFlagNeedsSetup verifies a stored flag from before
// setup is not reported as on, even when a node status is standing in as
// connected. The client offers setup; this response does not turn it on (#3611).
func TestGetRemoteAccess_StaleFlagNeedsSetup(t *testing.T) {
	engine := newSettingsEngine(t)
	if err := settingsutil.SetRemoteAccess(true); err != nil {
		t.Fatalf("SetRemoteAccess: %v", err)
	}
	restore := remoteutil.SetStatusForTesting(remoteutil.StatusResult{
		Connected: true,
		RemoteURL: "http://100.64.0.1:80",
		Error:     "stale",
	})
	t.Cleanup(restore)

	w := doSettingsReq(engine, http.MethodGet, "/api/v0/settings/remote-access", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /settings/remote-access returned %d: %s", w.Code, w.Body.String())
	}
	var raw map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &raw); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	if raw["enabled"] != false {
		t.Errorf("enabled = %v; want false until setup enrolls the Quark", raw["enabled"])
	}
	if raw["needsSetup"] != true {
		t.Errorf("needsSetup = %v; want true so the client can offer setup", raw["needsSetup"])
	}
	if raw["connected"] != false {
		t.Errorf("connected = %v; want false while setup is incomplete", raw["connected"])
	}
	if _, ok := raw["remoteUrl"]; ok {
		t.Errorf("remoteUrl = %v; want it omitted until setup is complete", raw["remoteUrl"])
	}
	if _, ok := raw["error"]; ok {
		t.Errorf("error = %v; want it omitted until setup is complete", raw["error"])
	}
}

// TestGetRemoteAccess_EnabledButNotConnected verifies the status reports the
// persisted setting as enabled while saying the node is not on the tailnet —
// the state a failed or still-authenticating boot leaves behind (#1815).
func TestGetRemoteAccess_EnabledButNotConnected(t *testing.T) {
	engine := newSettingsEngine(t)
	if err := settingsutil.SetRemoteAccess(true); err != nil {
		t.Fatalf("SetRemoteAccess: %v", err)
	}
	// Enrollment is what makes the flag count as on (#3611). A flag alone is
	// setup still to do.
	if err := settingsutil.SetHousehold("household", "token"); err != nil {
		t.Fatalf("SetHousehold: %v", err)
	}

	w := doSettingsReq(engine, http.MethodGet, "/api/v0/settings/remote-access", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /settings/remote-access returned %d: %s", w.Code, w.Body.String())
	}
	var raw map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &raw); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	if raw["enabled"] != true {
		t.Errorf("enabled = %v; want true (the persisted setting)", raw["enabled"])
	}
	if raw["connected"] != false {
		t.Errorf("connected = %v; want false with no node running", raw["connected"])
	}
	if _, ok := raw["remoteUrl"]; ok {
		t.Errorf("remoteUrl = %v; want it omitted while not connected", raw["remoteUrl"])
	}
}

// TestRemoteAccessToggle_NotOnPublicRouter verifies enabling and disabling
// remote access are absent from the router every signed-in user reaches; they
// live on NewAdminRouter, which routes.go mounts behind RequireAdmin.
func TestRemoteAccessToggle_NotOnPublicRouter(t *testing.T) {
	engine := newSettingsEngine(t)

	for _, method := range []string{http.MethodPost, http.MethodDelete} {
		w := doSettingsReq(engine, method, "/api/v0/settings/remote-access", []byte("{}"))
		if w.Code != http.StatusNotFound {
			t.Errorf("%s /settings/remote-access on the public router returned %d; want 404", method, w.Code)
		}
	}
}

// newAdminEngine mounts the admin settings routes with an isolated settings
// file and an empty $HOME, so tsnet finds no enrollment and never touches one
// that belongs to the machine running the test.
func newAdminEngine(t *testing.T) *gin.Engine {
	t.Helper()
	if runtime.GOOS == "linux" {
		if _, err := os.Stat("/var/lib/quark"); err == nil {
			t.Skip("tsnet state would live in the real service dir on this machine")
		}
	}
	t.Setenv("HOME", t.TempDir())
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	t.Cleanup(func() { _ = remoteutil.Disable() })
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_settings.NewAdminRouter())
	return engine
}

// TestEnableRemoteAccess_AsksServiceWithoutSecret verifies enable no longer
// demands a key (#1876) and that any build asks the provisioning service for
// one with no secret header (#1879) — for a JSON body and for none at all.
func TestEnableRemoteAccess_AsksServiceWithoutSecret(t *testing.T) {
	engine := newAdminEngine(t)
	var asked int
	provisioner := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked++
		if got := r.Header.Get("X-Provisioning-Secret"); got != "" {
			t.Errorf("X-Provisioning-Secret = %q; want none", got)
		}
		http.Error(w, `{"error":"rate limit exceeded"}`, http.StatusTooManyRequests)
	}))
	defer provisioner.Close()
	t.Setenv("QUARK_PROVISIONING_URL", provisioner.URL+"/provision")

	for _, body := range [][]byte{[]byte("{}"), nil} {
		w := doSettingsReq(engine, http.MethodPost, "/api/v0/settings/remote-access", body)
		if w.Code != http.StatusInternalServerError {
			t.Fatalf("POST %q returned %d; want 500: %s", body, w.Code, w.Body.String())
		}
	}
	if asked != 2 {
		t.Errorf("provisioning service asked %d times; want 2", asked)
	}
	if settingsutil.GetRemoteAccess() {
		t.Error("remote access persisted as on after a failed enable")
	}
}

// TestEnableRemoteAccess_ProvisioningRefused verifies a key request the
// service turns down fails the enable, leaves the setting off, and is
// recorded for GET.
func TestEnableRemoteAccess_ProvisioningRefused(t *testing.T) {
	engine := newAdminEngine(t)
	provisioner := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
	}))
	defer provisioner.Close()
	t.Setenv("QUARK_PROVISIONING_URL", provisioner.URL+"/provision")

	w := doSettingsReq(engine, http.MethodPost, "/api/v0/settings/remote-access", []byte("{}"))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("POST returned %d; want 500: %s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "401") {
		t.Errorf("body = %s; want the diagnostic kept out of the response", w.Body.String())
	}
	if settingsutil.GetRemoteAccess() {
		t.Error("remote access persisted as on after a failed enable")
	}
	if got := remoteutil.Status(); !strings.Contains(got.Error, "401") {
		t.Errorf("Status().Error = %q; want the provisioning failure recorded", got.Error)
	}
}

// TestGetRemoteAccessPaths_AdminOnly serves the path report on the admin
// router only, and answers a stopped node with an empty report rather than an
// error (#3883).
func TestGetRemoteAccessPaths_AdminOnly(t *testing.T) {
	if w := doSettingsReq(newSettingsEngine(t), http.MethodGet, "/api/v0/settings/remote-access/paths", nil); w.Code != http.StatusNotFound {
		t.Errorf("GET /settings/remote-access/paths on the public router returned %d; want 404", w.Code)
	}

	w := doSettingsReq(newAdminEngine(t), http.MethodGet, "/api/v0/settings/remote-access/paths", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /settings/remote-access/paths returned %d: %s", w.Code, w.Body.String())
	}
	var got map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got["connected"] != false {
		t.Errorf("connected = %v; want false with no node", got["connected"])
	}
	if peers, ok := got["peers"].([]any); !ok || len(peers) != 0 {
		t.Errorf("peers = %v; want an empty list", got["peers"])
	}
}
