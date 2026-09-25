package v0_settings_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// TestUpdateChat_AdminRouterOnly checks the chat switch is absent from the
// router every signed-in user reaches, and on the admin router turns chat
// off and on, refusing a body that does not say which.
func TestUpdateChat_AdminRouterOnly(t *testing.T) {
	public := newSettingsEngine(t)
	if w := doSettingsReq(public, http.MethodPut, "/api/v0/settings/chat", []byte(`{"enabled":false}`)); w.Code != http.StatusNotFound {
		t.Errorf("PUT on the public router = %d, want 404", w.Code)
	}

	engine := newSettingsEngineWithAdmin(t)
	if w := doSettingsReq(engine, http.MethodPut, "/api/v0/settings/chat", []byte(`{}`)); w.Code != http.StatusBadRequest {
		t.Errorf("PUT {} = %d, want 400", w.Code)
	}
	if !settingsutil.GetChatEnabled() {
		t.Fatal("a refused body changed the setting")
	}

	for _, enabled := range []bool{false, true} {
		raw, _ := json.Marshal(map[string]bool{"enabled": enabled})
		w := doSettingsReq(engine, http.MethodPut, "/api/v0/settings/chat", raw)
		if w.Code != http.StatusOK {
			t.Fatalf("PUT enabled=%v = %d: %s", enabled, w.Code, w.Body.String())
		}
		if settingsutil.GetChatEnabled() != enabled {
			t.Errorf("after PUT enabled=%v the setting is %v", enabled, settingsutil.GetChatEnabled())
		}
	}
}
