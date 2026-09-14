package settingsutil_test

import (
	"os"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// TestAccessRequests_DefaultOnAndRoundTrip checks requests are on with no
// settings file and with a file written before the setting existed, and that
// turning them off survives a reload.
func TestAccessRequests_DefaultOnAndRoundTrip(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetAccessRequestsEnabled() {
		t.Error("requests should be on with no settings file")
	}

	if err := os.WriteFile(path, []byte(`{"autoUpdate":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetAccessRequestsEnabled() {
		t.Error("requests should be on for a file that predates the setting")
	}

	if err := settingsutil.SetAccessRequestsEnabled(false); err != nil {
		t.Fatalf("turn off: %v", err)
	}
	settingsutil.ResetForTesting(path)
	if settingsutil.GetAccessRequestsEnabled() {
		t.Error("requests should stay off after a reload")
	}
	if !settingsutil.GetAutoUpdate() {
		t.Error("turning requests off lost another setting")
	}

	if err := settingsutil.SetAccessRequestsEnabled(true); err != nil {
		t.Fatalf("turn on: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"accessRequestsEnabled": true`) {
		t.Errorf("settings file %s does not record requests turned on", data)
	}
}

// TestAccessRequests_UnreadableSettingsAreOff checks a settings file that
// cannot be parsed keeps requests off rather than opening the sign-in page.
func TestAccessRequests_UnreadableSettingsAreOff(t *testing.T) {
	path := settingsFile(t)
	if err := os.WriteFile(path, []byte("{not json"), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	if settingsutil.GetAccessRequestsEnabled() {
		t.Error("an unparseable settings file turned requests on")
	}
}
