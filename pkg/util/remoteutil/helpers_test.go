package remoteutil

import (
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"tailscale.com/envknob"
)

// TestNewProxy_KeepsEnoughIdleConnections verifies the proxy keeps more than
// the default two idle loopback connections, so a remote client with several
// requests in flight does not make it open a fresh TLS connection, a full
// handshake each, for every one past the second (#2755).
func TestNewProxy_KeepsEnoughIdleConnections(t *testing.T) {
	target := &url.URL{Scheme: "https", Host: "localhost:443"}
	for _, localTLS := range []bool{true, false} {
		transport, ok := newProxy(target, localTLS).Transport.(*http.Transport)
		if !ok {
			t.Fatalf("localTLS=%v: Transport is %T; want *http.Transport", localTLS, newProxy(target, localTLS).Transport)
		}
		if transport.MaxIdleConnsPerHost < proxyMaxIdleConnsPerHost {
			t.Errorf("localTLS=%v: MaxIdleConnsPerHost = %d; want at least %d",
				localTLS, transport.MaxIdleConnsPerHost, proxyMaxIdleConnsPerHost)
		}
		if localTLS && (transport.TLSClientConfig == nil || !transport.TLSClientConfig.InsecureSkipVerify) {
			t.Errorf("localTLS: TLSClientConfig = %+v; want the loopback hop to accept the self-signed cert",
				transport.TLSClientConfig)
		}
	}
}

// TestStartLocked_DisablesLogUploadBeforeNode verifies startLocked turns off
// the networking library's diagnostic log upload before it builds a node, so
// nothing is sent to the library vendor in the window before the coordination
// server's first map response (#3786). The state directory cannot be created,
// so the node is never built and the switch must already be set.
func TestStartLocked_DisablesLogUploadBeforeNode(t *testing.T) {
	if runtime.GOOS == "linux" {
		if _, err := os.Stat("/var/lib/quark"); err == nil {
			t.Skip("stateDir() is the real service dir on this machine")
		}
	}
	envknob.SetenvForTest(t, "TS_NO_LOGS_NO_SUPPORT", "")
	home := filepath.Join(t.TempDir(), "not-a-directory")
	if err := os.WriteFile(home, nil, 0600); err != nil {
		t.Fatalf("write HOME placeholder: %v", err)
	}
	t.Setenv("HOME", home)

	mu.Lock()
	prevErr := lastErr
	err := startLocked("key")
	lastErr = prevErr
	stillRunning := running || srv != nil
	mu.Unlock()
	if stillRunning {
		t.Fatal("startLocked built a node while the state directory could not be created")
	}
	if err == nil {
		t.Fatal("startLocked() = nil; want a state directory error")
	}
	if !envknob.NoLogsNoSupport() {
		t.Fatal("NoLogsNoSupport() = false after startLocked; want log upload off before the node is built")
	}
}
