package v0_settings_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	v0_settings "github.com/autobutler-org/quark/internal/server/api/v0/settings"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// newPairEngine mounts the non-admin settings router the way routes.go does,
// with username standing in for what requireAuth puts on the context; empty
// means an unauthenticated request. The Quark starts enrolled, on, and
// connected; each test turns off what it is about.
func newPairEngine(t *testing.T, username string) *gin.Engine {
	t.Helper()
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	if err := settingsutil.SetRemoteAccess(true); err != nil {
		t.Fatal(err)
	}
	if err := settingsutil.SetHousehold("household-abc", "token-abc"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(remoteutil.SetStatusForTesting(remoteutil.StatusResult{Connected: true, RemoteURL: "http://100.64.0.7:80"}))
	t.Setenv("QUARK_HEADSCALE_URL", "")

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		if username != "" {
			c = ctxutil.With(c, "username", username)
		}
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_settings.NewRouter())
	return engine
}

// fakeProvisioner stands in for cmd/provisioning in pair mode and counts the
// requests it answers.
func fakeProvisioner(t *testing.T) *int {
	t.Helper()
	calls := 0
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		var req struct {
			DeviceID       string `json:"device_id"`
			Household      string `json:"household"`
			HouseholdToken string `json:"household_token"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Errorf("decode provision request: %v", err)
		}
		if req.Household != "household-abc" || req.HouseholdToken != "token-abc" || !strings.HasPrefix(req.DeviceID, "pair-") {
			t.Errorf("provision request = %+v; want pair mode with the stored household and a device id", req)
		}
		_ = json.NewEncoder(w).Encode(map[string]string{
			"auth_key": "hskey-phone", "household": req.Household, "household_token": req.HouseholdToken,
		})
	}))
	t.Cleanup(ts.Close)
	t.Setenv("QUARK_PROVISIONING_URL", ts.URL+"/provision")
	return &calls
}

const pairPath = "/api/v0/settings/remote-access/devices"

func TestPairDevice_NonAdminGetsKey(t *testing.T) {
	engine := newPairEngine(t, "alice")
	calls := fakeProvisioner(t)

	w := doSettingsReq(engine, http.MethodPost, pairPath, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("POST returned %d; want 200: %s", w.Code, w.Body.String())
	}
	var got v0_settings.PairDeviceResponse
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	want := v0_settings.PairDeviceResponse{
		AuthKey:      "hskey-phone",
		ControlURL:   "https://quark.ts.autobutler.org",
		QuarkAddress: "http://100.64.0.7:80",
	}
	if got != want {
		t.Errorf("response = %+v; want %+v", got, want)
	}
	if *calls != 1 {
		t.Errorf("provisioning service called %d times; want 1", *calls)
	}
}

// TestPairDevice_Refusals verifies each state a key could not be used in is
// refused with a message saying what to do, without asking for a key.
func TestPairDevice_Refusals(t *testing.T) {
	cases := []struct {
		name    string
		arrange func(t *testing.T)
		code    int
		message string
	}{
		{"custom tailnet", func(t *testing.T) {
			t.Setenv("QUARK_HEADSCALE_URL", "https://headscale.example.com")
		}, http.StatusConflict, "add the device there"},
		{"remote access off", func(t *testing.T) {
			if err := settingsutil.SetRemoteAccess(false); err != nil {
				t.Fatal(err)
			}
		}, http.StatusConflict, "ask an admin to turn it on"},
		{"no household", func(t *testing.T) {
			if err := settingsutil.SetHousehold("", ""); err != nil {
				t.Fatal(err)
			}
		}, http.StatusConflict, "turn remote access off and on again"},
		{"still connecting", func(t *testing.T) {
			t.Cleanup(remoteutil.SetStatusForTesting(remoteutil.StatusResult{}))
		}, http.StatusServiceUnavailable, "try again in a moment"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			engine := newPairEngine(t, "alice")
			calls := fakeProvisioner(t)
			tc.arrange(t)

			w := doSettingsReq(engine, http.MethodPost, pairPath, nil)
			if w.Code != tc.code || !strings.Contains(w.Body.String(), tc.message) {
				t.Errorf("POST returned %d %s; want %d saying %q", w.Code, w.Body.String(), tc.code, tc.message)
			}
			if *calls != 0 {
				t.Errorf("provisioning service called %d times; want none", *calls)
			}
		})
	}
}

func TestPairDevice_Unauthenticated(t *testing.T) {
	engine := newPairEngine(t, "")
	calls := fakeProvisioner(t)

	if w := doSettingsReq(engine, http.MethodPost, pairPath, nil); w.Code != http.StatusUnauthorized {
		t.Errorf("POST returned %d; want 401", w.Code)
	}
	if *calls != 0 {
		t.Errorf("provisioning service called %d times; want none", *calls)
	}
}
