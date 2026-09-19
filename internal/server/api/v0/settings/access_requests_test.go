package v0_settings_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// TestUpdateAccessRequests_AdminRouterOnly checks the toggle is absent from the
// router every signed-in user reaches, and on the admin router turns requests
// off and on, refusing a body that does not say which.
func TestUpdateAccessRequests_AdminRouterOnly(t *testing.T) {
	public := newSettingsEngine(t)
	if w := doSettingsReq(public, http.MethodPut, "/api/v0/settings/access-requests", []byte(`{"enabled":false}`)); w.Code != http.StatusNotFound {
		t.Errorf("PUT on the public router = %d, want 404", w.Code)
	}

	engine := newSettingsEngineWithAdmin(t)
	for _, body := range [][]byte{nil, []byte(`{}`), []byte(`{"enabled":"no"}`)} {
		if w := doSettingsReq(engine, http.MethodPut, "/api/v0/settings/access-requests", body); w.Code != http.StatusBadRequest {
			t.Errorf("PUT %q = %d, want 400", body, w.Code)
		}
	}
	if !settingsutil.GetAccessRequestsEnabled() {
		t.Fatal("a refused body changed the setting")
	}

	for _, enabled := range []bool{false, true} {
		raw, _ := json.Marshal(map[string]bool{"enabled": enabled})
		w := doSettingsReq(engine, http.MethodPut, "/api/v0/settings/access-requests", raw)
		if w.Code != http.StatusOK {
			t.Fatalf("PUT enabled=%v = %d: %s", enabled, w.Code, w.Body.String())
		}
		var got struct {
			Enabled bool `json:"enabled"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if got.Enabled != enabled || settingsutil.GetAccessRequestsEnabled() != enabled {
			t.Errorf("after PUT enabled=%v: body %v, setting %v", enabled, got.Enabled, settingsutil.GetAccessRequestsEnabled())
		}
	}
}
