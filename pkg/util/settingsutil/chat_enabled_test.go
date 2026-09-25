package settingsutil_test

import (
	"os"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// TestChatEnabled_DefaultOnAndRoundTrip checks chat is on with no settings
// file and with one written before the setting existed, and that turning it
// off survives a reload without touching other settings.
func TestChatEnabled_DefaultOnAndRoundTrip(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetChatEnabled() {
		t.Error("chat should be on with no settings file")
	}

	if err := os.WriteFile(path, []byte(`{"autoUpdate":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetChatEnabled() {
		t.Error("chat should be on for a file that predates the setting")
	}

	if err := settingsutil.SetChatEnabled(false); err != nil {
		t.Fatalf("turn off: %v", err)
	}
	settingsutil.ResetForTesting(path)
	if settingsutil.GetChatEnabled() {
		t.Error("chat should stay off after a reload")
	}
	if !settingsutil.GetAutoUpdate() {
		t.Error("turning chat off lost another setting")
	}

	if err := settingsutil.SetChatEnabled(true); err != nil {
		t.Fatalf("turn on: %v", err)
	}
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetChatEnabled() {
		t.Error("chat should be on again after a reload")
	}
}
