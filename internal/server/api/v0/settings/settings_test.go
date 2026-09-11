package v0_settings_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	v0_settings "github.com/autobutler-org/quark/internal/server/api/v0/settings"
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

// TestGetSettings_DefaultAutoUpdate verifies GET /settings returns autoUpdate=false
// (the zero-value default) when no settings file exists.
func TestGetSettings_DefaultAutoUpdate(t *testing.T) {
	engine := newSettingsEngine(t)

	w := doSettingsReq(engine, http.MethodGet, "/api/v0/settings", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /settings returned %d: %s", w.Code, w.Body.String())
	}

	var s v0_settings.SettingsJSON
	if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	if s.AutoUpdate {
		t.Error("expected autoUpdate=false (default), got true")
	}
}

// TestPostSettings_UpdateAutoUpdate verifies POST /settings persists autoUpdate=true
// and is reflected in a subsequent GET.
func TestPostSettings_UpdateAutoUpdate(t *testing.T) {
	engine := newSettingsEngine(t)

	body, _ := json.Marshal(v0_settings.SettingsJSON{AutoUpdate: true})
	w := doSettingsReq(engine, http.MethodPost, "/api/v0/settings", body)
	if w.Code != http.StatusOK {
		t.Fatalf("POST /settings returned %d: %s", w.Code, w.Body.String())
	}

	var resp v0_settings.SettingsJSON
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal POST response: %v", err)
	}
	if !resp.AutoUpdate {
		t.Error("POST response: expected autoUpdate=true")
	}

	// Verify persistence via GET.
	w2 := doSettingsReq(engine, http.MethodGet, "/api/v0/settings", nil)
	if w2.Code != http.StatusOK {
		t.Fatalf("GET /settings returned %d: %s", w2.Code, w2.Body.String())
	}
	var s v0_settings.SettingsJSON
	if err := json.Unmarshal(w2.Body.Bytes(), &s); err != nil {
		t.Fatalf("unmarshal GET response: %v", err)
	}
	if !s.AutoUpdate {
		t.Error("GET after POST: expected autoUpdate=true to persist")
	}
}

// TestPostSettings_InvalidBody verifies POST /settings returns 400 for malformed JSON.
func TestPostSettings_InvalidBody(t *testing.T) {
	engine := newSettingsEngine(t)

	w := doSettingsReq(engine, http.MethodPost, "/api/v0/settings", []byte("not-json{{{"))
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

// TestPostSettings_DisableAutoUpdate verifies toggling autoUpdate off after it
// was enabled.
func TestPostSettings_DisableAutoUpdate(t *testing.T) {
	engine := newSettingsEngine(t)

	// Enable.
	body, _ := json.Marshal(v0_settings.SettingsJSON{AutoUpdate: true})
	doSettingsReq(engine, http.MethodPost, "/api/v0/settings", body)

	// Disable.
	body, _ = json.Marshal(v0_settings.SettingsJSON{AutoUpdate: false})
	w := doSettingsReq(engine, http.MethodPost, "/api/v0/settings", body)
	if w.Code != http.StatusOK {
		t.Fatalf("POST /settings returned %d: %s", w.Code, w.Body.String())
	}

	w2 := doSettingsReq(engine, http.MethodGet, "/api/v0/settings", nil)
	var s v0_settings.SettingsJSON
	if err := json.Unmarshal(w2.Body.Bytes(), &s); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if s.AutoUpdate {
		t.Error("expected autoUpdate=false after disabling")
	}
}

// TestGetSettings_ResponseShape verifies the response JSON has the expected fields.
func TestGetSettings_ResponseShape(t *testing.T) {
	engine := newSettingsEngine(t)

	w := doSettingsReq(engine, http.MethodGet, "/api/v0/settings", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /settings returned %d: %s", w.Code, w.Body.String())
	}

	var raw map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &raw); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	if _, ok := raw["autoUpdate"]; !ok {
		t.Error("response missing 'autoUpdate' field")
	}
}

// TestGetRemoteAccess_EnabledButNotConnected verifies the status reports the
// persisted setting as enabled while saying the node is not on the tailnet —
// the state a failed or still-authenticating boot leaves behind (#1815).
func TestGetRemoteAccess_EnabledButNotConnected(t *testing.T) {
	engine := newSettingsEngine(t)
	if err := settingsutil.SetRemoteAccess(true, "a-key"); err != nil {
		t.Fatalf("SetRemoteAccess: %v", err)
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

// TestEnableRemoteAccess_NoKeySaysProvisioningIsUnavailable verifies the 400
// the app gets today tells the truth about why.
func TestEnableRemoteAccess_NoKeySaysProvisioningIsUnavailable(t *testing.T) {
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_settings.NewAdminRouter())

	w := doSettingsReq(engine, http.MethodPost, "/api/v0/settings/remote-access", []byte("{}"))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("POST /settings/remote-access returned %d; want 400: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "automatic provisioning is not available yet") {
		t.Errorf("body = %s; want it to say provisioning is not available yet", w.Body.String())
	}
}
