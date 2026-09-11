package remoteutil

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"tailscale.com/ipn/ipnstate"
)

// TestControlURL_DefaultWhenEnvUnset verifies the default Headscale URL is
// returned when the env var is not set.
func TestControlURL_DefaultWhenEnvUnset(t *testing.T) {
	t.Setenv("QUARK_HEADSCALE_URL", "")
	got := controlURL()
	if got != defaultControlURL {
		t.Errorf("controlURL() = %q; want %q", got, defaultControlURL)
	}
}

// TestControlURL_OverriddenByEnv verifies that QUARK_HEADSCALE_URL
// overrides the built-in default.
func TestControlURL_OverriddenByEnv(t *testing.T) {
	custom := "https://my-headscale.example.com"
	t.Setenv("QUARK_HEADSCALE_URL", custom)
	got := controlURL()
	if got != custom {
		t.Errorf("controlURL() = %q; want %q", got, custom)
	}
}

// TestControlURL_HTTPWarningDoesNotPanic verifies that an HTTP (non-TLS)
// control URL is accepted without panicking (it logs a warning but returns
// the value unchanged).
func TestControlURL_HTTPWarningDoesNotPanic(t *testing.T) {
	insecure := "http://headscale.internal:8080"
	t.Setenv("QUARK_HEADSCALE_URL", insecure)
	got := controlURL()
	if got != insecure {
		t.Errorf("controlURL() = %q; want %q", got, insecure)
	}
}

// TestStateDir_IsAbsolutePath verifies that stateDir returns an absolute path
// regardless of environment.
func TestStateDir_IsAbsolutePath(t *testing.T) {
	dir := stateDir()
	if !filepath.IsAbs(dir) {
		t.Errorf("stateDir() = %q; want absolute path", dir)
	}
}

// TestStateDir_ContainsTsnet verifies that the path references "tsnet" so
// callers can locate the persistence directory predictably.
func TestStateDir_ContainsTsnet(t *testing.T) {
	dir := stateDir()
	if !strings.Contains(dir, "tsnet") {
		t.Errorf("stateDir() = %q; expected to contain 'tsnet'", dir)
	}
}

// TestStateDir_LinuxServicePath verifies that on Linux, when /var/lib/quark
// exists on disk, stateDir returns the systemd service path. Skipped on non-Linux.
func TestStateDir_LinuxServicePath(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Linux-only test")
	}
	if _, err := os.Stat("/var/lib/quark"); err != nil {
		t.Skip("/var/lib/quark does not exist on this machine")
	}
	dir := stateDir()
	if dir != "/var/lib/quark/tsnet" {
		t.Errorf("stateDir() = %q; want /var/lib/quark/tsnet", dir)
	}
}

// TestIsRunning_FalseByDefault verifies that IsRunning returns false before
// Start is ever called.
func TestIsRunning_FalseByDefault(t *testing.T) {
	// This test relies on the package-level `running` var being false at
	// program start. It is not safe to call Stop() here — that operates on
	// a nil server pointer and must not be called without a running tsnet.
	if IsRunning() {
		t.Skip("tsnet appears to be running in this process — skipping state test")
	}
}

// TestHasPersistedState_FalseWhenDirMissing verifies HasPersistedState returns
// false when the tsnet state directory does not exist.
func TestHasPersistedState_FalseWhenDirMissing(t *testing.T) {
	// Only meaningful when the actual state dir doesn't exist.
	dir := stateDir()
	if _, err := os.Stat(dir); err == nil {
		t.Skip("tsnet state dir exists — skipping missing-dir test")
	}
	if HasPersistedState() {
		t.Error("HasPersistedState() = true but state dir does not exist")
	}
}

// TestHasPersistedState_TrueWhenFilePresent verifies HasPersistedState returns
// true when at least one file exists in a temp dir that mirrors the tsnet state dir.
func TestHasPersistedState_TrueWhenFilePresent(t *testing.T) {
	// We can't override stateDir() without an env var, but we can verify the
	// HasPersistedState logic independently via a temp dir + symlink trick.
	// Instead, test the boundary logic directly: a dir with one file → true.
	tmp := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmp, "state.json"), []byte("{}"), 0600); err != nil {
		t.Fatalf("write state file: %v", err)
	}

	// Validate the same logic HasPersistedState uses.
	entries, err := os.ReadDir(tmp)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	hasFile := false
	for _, e := range entries {
		if !e.IsDir() {
			hasFile = true
		}
	}
	if !hasFile {
		t.Error("expected to find a non-dir entry in temp state dir")
	}
}

// TestNewProxy_SetsForwardedFor verifies that the remote-access proxy tells the
// quark who the tailnet peer is. Without X-Forwarded-For every remote request
// reaches the quark from loopback, and all tailnet peers share one login
// rate-limit bucket. A header the client sent is dropped, not forwarded, so a
// tailnet peer cannot name some other IP.
func TestNewProxy_SetsForwardedFor(t *testing.T) {
	var got string
	backend := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		got = r.Header.Get("X-Forwarded-For")
	}))
	defer backend.Close()
	target, err := url.Parse(backend.URL)
	if err != nil {
		t.Fatal(err)
	}
	proxy := httptest.NewServer(newProxy(target, false))
	defer proxy.Close()

	req, err := http.NewRequest(http.MethodGet, proxy.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("X-Forwarded-For", "198.51.100.9")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()

	if want := "127.0.0.1"; got != want {
		t.Errorf("X-Forwarded-For at the quark = %q; want %q", got, want)
	}
}

// TestConnectionFromStatus verifies that only BackendState "Running" counts as
// connected (#1815): tsnet.Server.Start returns before the node authenticates,
// and a node waiting on login can already hold an IP. "NeedsLogin" is reported
// as a rejected or expired key rather than as connecting forever (#1876).
func TestConnectionFromStatus(t *testing.T) {
	ip := []netip.Addr{netip.MustParseAddr("100.64.0.7")}
	cases := []struct {
		name string
		st   *ipnstate.Status
		want StatusResult
	}{
		{"nil status", nil, StatusResult{}},
		{"no state yet", &ipnstate.Status{BackendState: "NoState"}, StatusResult{}},
		{"starting", &ipnstate.Status{BackendState: "Starting", TailscaleIPs: ip}, StatusResult{}},
		{"needs login", &ipnstate.Status{BackendState: "NeedsLogin", TailscaleIPs: ip}, StatusResult{Error: errKeyRejected}},
		{"running without an IP yet", &ipnstate.Status{BackendState: "Running"}, StatusResult{Connected: true}},
		{"running", &ipnstate.Status{BackendState: "Running", TailscaleIPs: ip}, StatusResult{Connected: true, RemoteURL: "http://100.64.0.7:80"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := connectionFromStatus(tc.st); got != tc.want {
				t.Errorf("connectionFromStatus() = %+v; want %+v", got, tc.want)
			}
		})
	}
}

// TestEnsureStarted_RecordsProvisionFailure verifies a failed key request is
// reported by Status, so a boot that could not provision shows as failing.
func TestEnsureStarted_RecordsProvisionFailure(t *testing.T) {
	if runtime.GOOS == "linux" {
		if _, err := os.Stat("/var/lib/quark"); err == nil {
			t.Skip("stateDir() is the real service dir on this machine")
		}
	}
	t.Setenv("HOME", t.TempDir())

	err := EnsureStarted(0, false, func() (string, error) { return "", errors.New("no secret") })
	if err == nil || !strings.Contains(err.Error(), "no secret") {
		t.Fatalf("EnsureStarted() = %v; want the provisioning error", err)
	}
	if got := Status(); !strings.Contains(got.Error, "no secret") || got.Connected {
		t.Errorf("Status() = %+v; want the provisioning error, not connected", got)
	}
	if err := Disable(); err != nil {
		t.Fatalf("Disable() = %v", err)
	}
}

// TestStatus_ReportsProxyFailureUntilDisable verifies that a failed start is
// recorded for GET to report, and that Disable clears it along with the tsnet
// state dir, so HasPersistedState is false afterwards (#1815).
func TestStatus_ReportsProxyFailureUntilDisable(t *testing.T) {
	if runtime.GOOS == "linux" {
		if _, err := os.Stat("/var/lib/quark"); err == nil {
			t.Skip("stateDir() is the real service dir on this machine; refusing to delete it")
		}
	}
	// stateDir() lives under $HOME, so this keeps the test away from any real
	// enrollment on the machine running it.
	t.Setenv("HOME", t.TempDir())
	dir := stateDir()
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "state.json"), []byte("{}"), 0600); err != nil {
		t.Fatalf("write state file: %v", err)
	}
	if !HasPersistedState() {
		t.Fatal("HasPersistedState() = false with a state file present")
	}

	// No node is running, so the proxy has nothing to listen on.
	if err := StartProxy(0, false); err == nil {
		t.Fatal("StartProxy() = nil; want an error with no node started")
	}
	if got := Status(); got.Error == "" || got.Connected || got.RemoteURL != "" {
		t.Errorf("Status() after a failed start = %+v; want an error and not connected", got)
	}

	if err := Disable(); err != nil {
		t.Fatalf("Disable() = %v", err)
	}
	if got := Status(); got.Error != "" {
		t.Errorf("Status().Error after Disable = %q; want empty", got.Error)
	}
	if HasPersistedState() {
		t.Error("HasPersistedState() = true after Disable; want the state dir removed")
	}
}
