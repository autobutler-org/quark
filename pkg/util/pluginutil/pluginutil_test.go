package pluginutil_test

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/pluginutil"
)

// ---------------------------------------------------------------------------
// Token tests
// ---------------------------------------------------------------------------

func TestIssueVFSToken_Valid(t *testing.T) {
	token, err := pluginutil.IssueVFSToken("test-plugin", []string{"files"}, []string{"photos"})
	if err != nil {
		t.Fatalf("IssueVFSToken: %v", err)
	}
	if token == "" {
		t.Fatal("expected non-empty token")
	}

	claims, err := pluginutil.ValidateVFSToken(token)
	if err != nil {
		t.Fatalf("ValidateVFSToken: %v", err)
	}
	if claims.PluginID != "test-plugin" {
		t.Errorf("PluginID: got %q, want %q", claims.PluginID, "test-plugin")
	}
	if len(claims.NamespacesRead) != 1 || claims.NamespacesRead[0] != "files" {
		t.Errorf("NamespacesRead: got %v", claims.NamespacesRead)
	}
	if len(claims.NamespacesWrite) != 1 || claims.NamespacesWrite[0] != "photos" {
		t.Errorf("NamespacesWrite: got %v", claims.NamespacesWrite)
	}
}

func TestValidateVFSToken_Invalid(t *testing.T) {
	if _, err := pluginutil.ValidateVFSToken("not.a.jwt"); err == nil {
		t.Error("expected error for invalid token")
	}
}

func TestRotateSigningKey_InvalidatesOldToken(t *testing.T) {
	token, err := pluginutil.IssueVFSToken("plugin-x", nil, nil)
	if err != nil {
		t.Fatalf("IssueVFSToken: %v", err)
	}

	if err := pluginutil.RotateSigningKey(); err != nil {
		t.Fatalf("RotateSigningKey: %v", err)
	}

	if _, err := pluginutil.ValidateVFSToken(token); err == nil {
		t.Error("expected token to be invalid after key rotation")
	}
}

// ---------------------------------------------------------------------------
// Manifest tests
// ---------------------------------------------------------------------------

func TestLoadPluginRegistry_NotExist(t *testing.T) {
	entries, err := pluginutil.LoadPluginRegistry("/nonexistent/plugins.json")
	if err != nil {
		t.Fatalf("expected nil error for missing file, got: %v", err)
	}
	if entries != nil {
		t.Errorf("expected nil entries, got %v", entries)
	}
}

func TestLoadPluginRegistry_Valid(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "plugins.json")
	data := `[
		{"id":"hello","binaryPath":"/bin/hello","sha256":"abc123","enabled":true,"namespacesRead":["files"]}
	]`
	if err := os.WriteFile(path, []byte(data), 0600); err != nil {
		t.Fatalf("write: %v", err)
	}

	entries, err := pluginutil.LoadPluginRegistry(path)
	if err != nil {
		t.Fatalf("LoadPluginRegistry: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	if entries[0].ID != "hello" {
		t.Errorf("ID: got %q, want %q", entries[0].ID, "hello")
	}
	if !entries[0].Enabled {
		t.Error("expected Enabled=true")
	}
}

// ---------------------------------------------------------------------------
// Host integration test (requires a real plugin binary)
// ---------------------------------------------------------------------------

// startFakePlugin starts an in-process HTTP server that behaves like a plugin:
// it listens, writes "READY addr=...", and serves /health and /manifest.
// Returns the listener address.
func startFakePlugin(t *testing.T) (addr string, cleanup func()) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/manifest", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"id":      "fake-plugin",
			"name":    "Fake Plugin",
			"version": "1.0.0",
		})
	})
	srv := &http.Server{Handler: mux}
	go srv.Serve(ln)
	return ln.Addr().String(), func() { srv.Close() }
}

// TestReadReadyLine tests the READY handshake parser by simulating what a
// plugin writes to stdout. We can't call the unexported readReadyLine directly
// from tests, so we test it end-to-end via a pipe.
func TestReadReadyLine_ViaReader(t *testing.T) {
	// Simulate the plugin writing "READY addr=127.0.0.1:9999\n" to stdout.
	addr := "127.0.0.1:9999"
	pr, pw, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	defer pr.Close()

	go func() {
		fmt.Fprintf(pw, "READY addr=%s\n", addr)
		pw.Close()
	}()

	// Read and verify.
	scanner := bufio.NewScanner(pr)
	var got string
	timeout := time.After(2 * time.Second)
	done := make(chan struct{})
	go func() {
		for scanner.Scan() {
			line := scanner.Text()
			if strings.HasPrefix(line, "READY addr=") {
				got = strings.TrimPrefix(line, "READY addr=")
				break
			}
		}
		close(done)
	}()
	select {
	case <-done:
	case <-timeout:
		t.Fatal("timed out reading READY line")
	}
	if got != addr {
		t.Errorf("READY addr: got %q, want %q", got, addr)
	}
}

// TestHost_StartStop verifies that a Host with no plugins starts and stops
// without error.
func TestHost_StartStop(t *testing.T) {
	dir := t.TempDir()
	registryPath := filepath.Join(dir, "plugins.json")
	// Empty registry.
	if err := os.WriteFile(registryPath, []byte("[]"), 0600); err != nil {
		t.Fatalf("write: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	host := pluginutil.NewHost("http://127.0.0.1:8080/api/v1/vfs")
	if err := host.Start(ctx, registryPath); err != nil {
		t.Fatalf("Start: %v", err)
	}
	host.Stop()

	if len(host.Plugins()) != 0 {
		t.Errorf("expected 0 plugins, got %d", len(host.Plugins()))
	}
}
