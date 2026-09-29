package settingsutil_test

import (
	"os"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// TestFeatureFlag_UnsetAndRoundTrip checks a flag nobody set reads as unset,
// and that a stored value survives a reload without touching other settings.
func TestFeatureFlag_UnsetAndRoundTrip(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)
	if _, set, err := settingsutil.GetFeatureFlag("chat"); err != nil || set {
		t.Fatalf("GetFeatureFlag with no file: set=%v err=%v; want unset", set, err)
	}
	if err := settingsutil.SetAutoUpdate(true); err != nil {
		t.Fatal(err)
	}

	for _, enabled := range []bool{false, true} {
		if err := settingsutil.SetFeatureFlag("chat", enabled); err != nil {
			t.Fatalf("SetFeatureFlag(%v): %v", enabled, err)
		}
		settingsutil.ResetForTesting(path)
		got, set, err := settingsutil.GetFeatureFlag("chat")
		if err != nil || !set || got != enabled {
			t.Errorf("after reload: %v set=%v err=%v; want %v", got, set, err, enabled)
		}
		if !settingsutil.GetAutoUpdate() {
			t.Error("setting a flag lost another setting")
		}
	}
}

// TestMigrate_ChatEnabledMovesToFeatureFlags checks a file #2421 wrote has
// its chatEnabled moved to featureFlags.chat and dropped on load.
func TestMigrate_ChatEnabledMovesToFeatureFlags(t *testing.T) {
	for _, tc := range []struct {
		file      string
		want, set bool
	}{
		{`{"autoUpdate":true,"chatEnabled":false}`, false, true},
		{`{"autoUpdate":true,"chatEnabled":true}`, true, true},
		{`{"autoUpdate":true}`, false, false},
	} {
		path := settingsFile(t)
		if err := os.WriteFile(path, []byte(tc.file), 0600); err != nil {
			t.Fatal(err)
		}
		settingsutil.ResetForTesting(path)
		got, set, err := settingsutil.GetFeatureFlag("chat")
		if err != nil || set != tc.set || got != tc.want {
			t.Errorf("%s: chat=%v set=%v err=%v; want %v set=%v", tc.file, got, set, err, tc.want, tc.set)
		}
		if !settingsutil.GetAutoUpdate() {
			t.Errorf("%s: autoUpdate lost", tc.file)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(data), "chatEnabled") {
			t.Errorf("%s: chatEnabled survived the migration:\n%s", tc.file, data)
		}
	}
}

// TestMigrate_RetiredFlagKeyRemoved checks retiring a flag, one
// dropFeatureFlag entry on the migration list, removes its persisted value on
// load and leaves the other flags alone.
func TestMigrate_RetiredFlagKeyRemoved(t *testing.T) {
	settingsutil.SetMigrationsForTesting(t,
		settingsutil.DropFeatureFlagForTesting("unused"),
		settingsutil.DropFeatureFlagForTesting("retired"),
	)
	path := settingsFile(t)
	file := `{"settingsVersion":1,"featureFlags":{"chat":false,"retired":true}}`
	if err := os.WriteFile(path, []byte(file), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)

	if _, set, err := settingsutil.GetFeatureFlag("retired"); err != nil || set {
		t.Errorf("retired flag still set after load (err=%v)", err)
	}
	if chat, set, _ := settingsutil.GetFeatureFlag("chat"); !set || chat {
		t.Error("retiring one flag changed another")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "retired") {
		t.Errorf("retired key still on disk:\n%s", data)
	}
}
