package settingsutil_test

import (
	"bytes"
	"database/sql"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// settingsFile returns the path used by settingsutil during the test.
func settingsFile(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "settings.json")
}

func TestGetSetRemoteAccess_RoundTrip(t *testing.T) {
	settingsutil.ResetForTesting(settingsFile(t))

	if settingsutil.GetRemoteAccess() {
		t.Error("expected enabled=false with no settings file")
	}
	if err := settingsutil.SetRemoteAccess(true); err != nil {
		t.Fatalf("SetRemoteAccess enable: %v", err)
	}
	if !settingsutil.GetRemoteAccess() {
		t.Error("expected enabled=true after enable")
	}
	if err := settingsutil.SetRemoteAccess(false); err != nil {
		t.Fatalf("SetRemoteAccess disable: %v", err)
	}
	if settingsutil.GetRemoteAccess() {
		t.Error("expected enabled=false after disable")
	}
}

func TestGetRemoteAccess_PersistsAcrossReset(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)

	if err := settingsutil.SetRemoteAccess(true); err != nil {
		t.Fatalf("SetRemoteAccess: %v", err)
	}

	// A restart: a new handle on the same database.
	settingsutil.ResetForTesting(path)

	if !settingsutil.GetRemoteAccess() {
		t.Error("expected enabled=true after a restart")
	}
}

// TestLegacyAuthKey_IgnoredAndDropped verifies a settings.json written before
// #1876, which still carries remoteAccessAuthKey, keeps its other settings on
// import, and that the stale key is not brought into the database.
func TestLegacyAuthKey_IgnoredAndDropped(t *testing.T) {
	path := settingsFile(t)
	legacy := `{"autoUpdate":true,"remoteAccessEnabled":true,"remoteAccessAuthKey":"hskey-old","devMode":false}`
	if err := os.WriteFile(path, []byte(legacy), 0600); err != nil {
		t.Fatalf("write legacy settings: %v", err)
	}
	settingsutil.ResetForTesting(path)

	if !settingsutil.GetRemoteAccess() || !settingsutil.GetAutoUpdate() {
		t.Fatal("legacy settings did not parse: want remote access and auto-update on")
	}
	_, err := settingsutil.QueriesForTesting().GetSetting(t.Context(), "remoteAccessAuthKey")
	if !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("the auth key was imported (err=%v); want no row", err)
	}
}

// TestImport_BringsInEverySettingOnce checks the upgrade path (#3083): every
// setting in an older build's settings.json is in the database after the
// first start, the file is set aside rather than deleted, and a file that
// turns up later does not overwrite what the database holds.
func TestImport_BringsInEverySettingOnce(t *testing.T) {
	path := settingsFile(t)
	secret := strings.Repeat("ab", 32)
	file := `{"settingsVersion":1,"autoUpdate":true,"remoteAccessEnabled":true,` +
		`"remoteAccessHousehold":"home","remoteAccessHouseholdToken":"tok","devMode":true,` +
		`"activeBranch":"dev","deviceId":"device-1","accessRequestsEnabled":false,` +
		`"featureFlags":{"chat":false,"slides":true},"themeColor":"#aabbcc","authSaltSecret":"` + secret + `"}`
	if err := os.WriteFile(path, []byte(file), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)

	off := false
	want := &settingsutil.Settings{
		SettingsVersion: 1, AutoUpdate: true, RemoteAccessEnabled: true,
		RemoteAccessHousehold: "home", RemoteAccessHouseholdToken: "tok", DevMode: true,
		ActiveBranch: "dev", DeviceID: "device-1", AccessRequestsEnabled: &off,
		FeatureFlags: map[string]bool{"chat": false, "slides": true}, ThemeColor: "#aabbcc", AuthSaltSecret: secret,
	}
	got, err := settingsutil.Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("imported settings = %+v\nwant %+v", got, want)
	}
	if got, err := settingsutil.AuthSaltSecret(); err != nil || hex.EncodeToString(got) != secret {
		t.Errorf("AuthSaltSecret = %x, %v; want the imported %s", got, err, secret)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("settings.json still in place after the import (err=%v)", err)
	}
	if kept, err := os.ReadFile(path + ".imported"); err != nil || string(kept) != file {
		t.Errorf("settings.json.imported = %q, %v; want the original file", kept, err)
	}

	if err := settingsutil.SetThemeColor("ocean"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(file), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	if got := settingsutil.GetThemeColor(); got != "ocean" {
		t.Errorf("theme color after a second import = %q; want the database's ocean", got)
	}
}

// TestSet_OneSettingNeverRevertsAnother checks what the settings table is
// for (#3083): two instances, which two handles on one database stand in for
// until the harness in #2971 exists, each change a different setting, and
// both changes are there for whoever reads next.
func TestSet_OneSettingNeverRevertsAnother(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)
	first := settingsutil.QueriesForTesting()
	if err := settingsutil.SetAutoUpdate(true); err != nil {
		t.Fatal(err)
	}

	settingsutil.ResetForTesting(path)
	if settingsutil.QueriesForTesting() == first {
		t.Fatal("the second instance has the first one's handle")
	}
	if !settingsutil.GetAutoUpdate() {
		t.Error("the second instance does not see the first one's change")
	}
	if err := settingsutil.SetThemeColor("ocean"); err != nil {
		t.Fatal(err)
	}
	if err := settingsutil.SetFeatureFlag("chat", true); err != nil {
		t.Fatal(err)
	}

	settingsutil.ResetForTesting(path)
	chat, set, err := settingsutil.GetFeatureFlag("chat")
	if !settingsutil.GetAutoUpdate() || settingsutil.GetThemeColor() != "ocean" || !chat || !set || err != nil {
		t.Errorf("autoUpdate=%v themeColor=%q chat=%v set=%v err=%v; want every change kept",
			settingsutil.GetAutoUpdate(), settingsutil.GetThemeColor(), chat, set, err)
	}
}

// TestAuthSaltSecret checks the salt secret is made once and survives a
// restart, which ResetForTesting on the same path stands in for.
func TestAuthSaltSecret(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	settingsutil.ResetForTesting(path)
	t.Cleanup(func() { settingsutil.ResetForTesting("") })

	first, err := settingsutil.AuthSaltSecret()
	if err != nil || len(first) != 32 {
		t.Fatalf("AuthSaltSecret = %d bytes, %v; want 32", len(first), err)
	}
	settingsutil.ResetForTesting(path)
	second, err := settingsutil.AuthSaltSecret()
	if err != nil || !bytes.Equal(first, second) {
		t.Errorf("AuthSaltSecret after a restart = %x, %v; want %x", second, err, first)
	}
}

// TestAuthSaltSecret_FirstUsesAgree checks instances that all find a fresh
// install with no secret end up with the same one (#3083): each offers its
// own and reads back the one the database kept.
func TestAuthSaltSecret_FirstUsesAgree(t *testing.T) {
	settingsutil.ResetForTesting(settingsFile(t))
	t.Cleanup(func() { settingsutil.ResetForTesting("") })

	const callers = 16
	secrets := make([][]byte, callers)
	errs := make([]error, callers)
	var wg sync.WaitGroup
	for i := range callers {
		wg.Go(func() { secrets[i], errs[i] = settingsutil.AuthSaltSecret() })
	}
	wg.Wait()

	for i := range callers {
		if errs[i] != nil || len(secrets[i]) != 32 || !bytes.Equal(secrets[i], secrets[0]) {
			t.Fatalf("caller %d got %x, %v; caller 0 got %x", i, secrets[i], errs[i], secrets[0])
		}
	}
}

// TestAuthSaltSecret_ReplacesWhatIsNotASecret checks a stored value that is
// not 32 bytes of hex is replaced rather than handed out or left to fail
// every request.
func TestAuthSaltSecret_ReplacesWhatIsNotASecret(t *testing.T) {
	path := settingsFile(t)
	if err := os.WriteFile(path, []byte(`{"authSaltSecret":"not hex"}`), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	t.Cleanup(func() { settingsutil.ResetForTesting("") })

	first, err := settingsutil.AuthSaltSecret()
	if err != nil || len(first) != 32 {
		t.Fatalf("AuthSaltSecret = %d bytes, %v; want 32", len(first), err)
	}
	if second, err := settingsutil.AuthSaltSecret(); err != nil || !bytes.Equal(first, second) {
		t.Errorf("second AuthSaltSecret = %x, %v; want %x", second, err, first)
	}
}

// TestUnbound checks the package says so when nothing gave it a database,
// and that the getters fall back to off rather than panic.
func TestUnbound(t *testing.T) {
	settingsutil.ResetForTesting("")
	if _, err := settingsutil.Load(); !errors.Is(err, settingsutil.ErrNotBound) {
		t.Errorf("Load unbound: %v; want ErrNotBound", err)
	}
	if err := settingsutil.SetAutoUpdate(true); !errors.Is(err, settingsutil.ErrNotBound) {
		t.Errorf("SetAutoUpdate unbound: %v; want ErrNotBound", err)
	}
	if _, err := settingsutil.AuthSaltSecret(); !errors.Is(err, settingsutil.ErrNotBound) {
		t.Errorf("AuthSaltSecret unbound: %v; want ErrNotBound", err)
	}
	if settingsutil.GetAutoUpdate() || settingsutil.GetAccessRequestsEnabled() {
		t.Error("an unbound getter answered on")
	}
}
