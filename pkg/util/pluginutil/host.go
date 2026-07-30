package pluginutil

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

const (
	readyTimeout     = 10 * time.Second
	healthInterval   = 30 * time.Second
	healthTimeout    = 5 * time.Second
	restartBaseDelay = time.Second
	restartMaxDelay  = 60 * time.Second
	shutdownDrain    = 10 * time.Second
)

// PluginState is the runtime state of a single running plugin.
type PluginState struct {
	Entry    PluginEntry
	Manifest *PluginManifest
	Addr     string // host:port the plugin is listening on
	Proxy    *httputil.ReverseProxy
}

// Host manages the lifecycle of all plugin subprocesses.
type Host struct {
	mu       sync.RWMutex
	plugins  map[string]*PluginState // keyed by plugin ID
	vfsBase  string                  // e.g. "http://127.0.0.1:8080/api/v1/vfs"
	cancelFn context.CancelFunc
}

// NewHost creates a plugin Host. Call Start to spawn configured plugins.
func NewHost(vfsBaseURL string) *Host {
	return &Host{
		plugins: make(map[string]*PluginState),
		vfsBase: vfsBaseURL,
	}
}

// Start loads plugins from registryPath and spawns all enabled entries.
// Blocks until the context is cancelled or all plugins have been launched.
func (h *Host) Start(ctx context.Context, registryPath string) error {
	ctx, cancel := context.WithCancel(ctx)
	h.cancelFn = cancel

	entries, err := LoadPluginRegistry(registryPath)
	if err != nil {
		cancel()
		return fmt.Errorf("load plugin registry: %w", err)
	}

	for _, entry := range entries {
		if !entry.Enabled {
			log.Printf("[plugin] %s: disabled, skipping", entry.ID)
			continue
		}
		if err := verifyBinary(entry); err != nil {
			log.Printf("[plugin] %s: binary verification failed: %v", entry.ID, err)
			continue
		}
		go h.runPlugin(ctx, entry, restartBaseDelay)
	}
	return nil
}

// Stop signals all plugins to shut down gracefully.
func (h *Host) Stop() {
	if h.cancelFn != nil {
		h.cancelFn()
	}
}

// Plugins returns a snapshot of all running plugin states (for the manifest
// aggregation endpoint).
func (h *Host) Plugins() []*PluginState {
	h.mu.RLock()
	defer h.mu.RUnlock()
	out := make([]*PluginState, 0, len(h.plugins))
	for _, s := range h.plugins {
		out = append(out, s)
	}
	return out
}

// Plugin returns the state for a single plugin ID, or (nil, false) if unknown.
func (h *Host) Plugin(id string) (*PluginState, bool) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	s, ok := h.plugins[id]
	return s, ok
}

// runPlugin starts a single plugin and restarts it on failure using
// exponential backoff. It runs until ctx is cancelled.
func (h *Host) runPlugin(ctx context.Context, entry PluginEntry, delay time.Duration) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		state, err := h.spawnPlugin(ctx, entry)
		if err != nil {
			log.Printf("[plugin] %s: spawn failed: %v; retrying in %s", entry.ID, err, delay)
		} else {
			h.mu.Lock()
			h.plugins[entry.ID] = state
			h.mu.Unlock()

			log.Printf("[plugin] %s: running at %s", entry.ID, state.Addr)
			delay = restartBaseDelay // reset backoff on successful start

			// Block until health check fails or context cancelled.
			h.watchPlugin(ctx, entry.ID, state)

			h.mu.Lock()
			delete(h.plugins, entry.ID)
			h.mu.Unlock()
		}

		select {
		case <-ctx.Done():
			return
		case <-time.After(delay):
			delay = min(delay*2, restartMaxDelay)
		}
	}
}

// spawnPlugin forks the plugin binary, waits for READY, fetches the manifest,
// and returns the fully initialised PluginState.
func (h *Host) spawnPlugin(ctx context.Context, entry PluginEntry) (*PluginState, error) {
	token, err := IssueVFSToken(entry.ID, entry.NamespacesRead, entry.NamespacesWrite)
	if err != nil {
		return nil, fmt.Errorf("issue VFS token: %w", err)
	}

	cmd := exec.CommandContext(ctx, entry.BinaryPath, "--addr", "127.0.0.1:0", "--plugin-id", entry.ID)
	cmd.Env = append(os.Environ(),
		"AUTOBUTLER_PLUGIN_ADDR=127.0.0.1:0",
		fmt.Sprintf("AUTOBUTLER_VFS_TOKEN=%s", token),
		fmt.Sprintf("AUTOBUTLER_VFS_BASE_URL=%s", h.vfsBase),
		fmt.Sprintf("AUTOBUTLER_PLUGIN_ID=%s", entry.ID),
	)

	// Capture stdout for the READY line; forward stderr to the logger.
	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("stdout pipe: %w", err)
	}
	cmd.Stderr = &prefixWriter{prefix: fmt.Sprintf("[plugin/%s] ", entry.ID)}

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start: %w", err)
	}

	// Wait for "READY addr=<host:port>" within the deadline.
	addr, err := readReadyLine(stdoutPipe, readyTimeout)
	if err != nil {
		_ = cmd.Process.Kill()
		return nil, fmt.Errorf("READY handshake: %w", err)
	}

	// Drain remaining stdout in background (plugins may log to stdout after READY).
	go io.Copy(io.Discard, stdoutPipe)

	// Fetch the manifest from the running plugin.
	manifest, err := fetchManifest(addr)
	if err != nil {
		log.Printf("[plugin] %s: manifest fetch failed: %v (continuing without manifest)", entry.ID, err)
	}

	// Build reverse proxy.
	target := &url.URL{Scheme: "http", Host: addr}
	proxy := httputil.NewSingleHostReverseProxy(target)

	return &PluginState{
		Entry:    entry,
		Manifest: manifest,
		Addr:     addr,
		Proxy:    proxy,
	}, nil
}

// watchPlugin polls the plugin's /health endpoint until it fails or ctx ends.
func (h *Host) watchPlugin(ctx context.Context, id string, state *PluginState) {
	ticker := time.NewTicker(healthInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := healthCheck(state.Addr); err != nil {
				log.Printf("[plugin] %s: health check failed: %v; restarting", id, err)
				return
			}
		}
	}
}

// readReadyLine reads from r until it receives a line starting with "READY addr=",
// or until timeout expires.
func readReadyLine(r io.Reader, timeout time.Duration) (string, error) {
	type result struct {
		addr string
		err  error
	}
	ch := make(chan result, 1)
	go func() {
		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			line := scanner.Text()
			if strings.HasPrefix(line, "READY addr=") {
				ch <- result{addr: strings.TrimPrefix(line, "READY addr=")}
				return
			}
		}
		if err := scanner.Err(); err != nil {
			ch <- result{err: err}
		} else {
			ch <- result{err: fmt.Errorf("process exited before READY")}
		}
	}()
	select {
	case res := <-ch:
		if res.err != nil {
			return "", res.err
		}
		return res.addr, nil
	case <-time.After(timeout):
		return "", fmt.Errorf("timed out after %s waiting for READY", timeout)
	}
}

// fetchManifest calls GET /manifest on the plugin and returns the decoded manifest.
func fetchManifest(addr string) (*PluginManifest, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		fmt.Sprintf("http://%s/manifest", addr), nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("manifest: HTTP %d", resp.StatusCode)
	}
	var m PluginManifest
	if err := json.NewDecoder(resp.Body).Decode(&m); err != nil {
		return nil, err
	}
	return &m, nil
}

// healthCheck calls GET /health on the plugin and returns an error if the
// plugin is not healthy.
func healthCheck(addr string) error {
	ctx, cancel := context.WithTimeout(context.Background(), healthTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		fmt.Sprintf("http://%s/health", addr), nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("health: HTTP %d", resp.StatusCode)
	}
	return nil
}

// verifyBinary checks that the binary exists and matches the expected SHA-256.
func verifyBinary(entry PluginEntry) error {
	f, err := os.Open(entry.BinaryPath)
	if err != nil {
		return fmt.Errorf("open binary: %w", err)
	}
	defer f.Close()

	if entry.SHA256 == "" {
		// No checksum configured — warn but allow (dev mode).
		log.Printf("[plugin] %s: WARNING: no SHA-256 configured, skipping integrity check", entry.ID)
		return nil
	}

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("hash binary: %w", err)
	}
	got := hex.EncodeToString(h.Sum(nil))
	if got != entry.SHA256 {
		return fmt.Errorf("SHA-256 mismatch: expected %s, got %s", entry.SHA256, got)
	}
	return nil
}

// prefixWriter is an io.Writer that prepends a prefix to every line.
type prefixWriter struct {
	prefix string
}

func (pw *prefixWriter) Write(p []byte) (int, error) {
	lines := strings.Split(string(p), "\n")
	for _, line := range lines {
		if line != "" {
			log.Print(pw.prefix + line)
		}
	}
	return len(p), nil
}

// ErrPluginNotFound returns an error describing a missing plugin.
func ErrPluginNotFound(id string) error {
	return fmt.Errorf("plugin %q not found or not running", id)
}

func min(a, b time.Duration) time.Duration {
	if a < b {
		return a
	}
	return b
}
