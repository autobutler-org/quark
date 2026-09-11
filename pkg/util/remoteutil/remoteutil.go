// Package remoteutil runs an embedded Tailscale node and reverse-proxies
// tailnet traffic to the local quark server.
package remoteutil

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

const hostname = "quark"

const defaultControlURL = "https://network.quark.org"

var (
	mu      sync.Mutex
	srv     *tsnet.Server
	proxyLn net.Listener
	running bool
)

func Start(authKey string) error {
	mu.Lock()
	defer mu.Unlock()
	if running {
		return nil
	}
	dir := stateDir()
	if err := os.MkdirAll(dir, 0700); err != nil {
		return fmt.Errorf("failed to create tsnet state dir: %w", err)
	}
	srv = &tsnet.Server{
		Hostname:   hostname,
		AuthKey:    authKey,
		Dir:        dir,
		ControlURL: controlURL(),
		Logf: func(format string, args ...any) {
			log.Printf("[tsnet] "+format, args...)
		},
	}
	if err := srv.Start(); err != nil {
		srv = nil
		return fmt.Errorf("failed to start tsnet: %w", err)
	}
	running = true
	return nil
}

func Stop() {
	mu.Lock()
	defer mu.Unlock()
	if proxyLn != nil {
		proxyLn.Close()
		proxyLn = nil
	}
	if srv != nil {
		srv.Close()
		srv = nil
	}
	running = false
}

func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return running
}

// RemoteURL returns the Tailscale IP-based URL for the tsnet node, or "" if
// not running. The mutex is held only long enough to snapshot the server
// pointer; the network call to the local Tailscale daemon happens outside the
// lock so that Stop() and IsRunning() are never blocked by I/O.
func RemoteURL() string {
	mu.Lock()
	if !running || srv == nil {
		mu.Unlock()
		return ""
	}
	s := srv
	mu.Unlock()

	lc, err := s.LocalClient()
	if err != nil {
		return ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	st, err := lc.Status(ctx)
	if err != nil {
		return ""
	}
	if st.Self == nil || len(st.Self.TailscaleIPs) == 0 {
		return ""
	}
	ip := st.Self.TailscaleIPs[0].String()
	return fmt.Sprintf("http://%s:80", ip)
}

// StartProxy starts an HTTP reverse proxy on the tsnet listener at :80,
// forwarding traffic to the local quark server at localPort. It is idempotent:
// if the proxy listener is already open, it returns nil immediately.
//
// The proxy is intentionally unauthenticated at the tsnet layer — access
// control is enforced by the proxied quark server's own auth middleware. Only
// peers on the tailnet can reach this listener.
// HasPersistedState returns true if tsnet has previously stored credentials
// on disk and can reconnect without a new auth key.
func HasPersistedState() bool {
	dir := stateDir()
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	for _, e := range entries {
		if !e.IsDir() {
			return true
		}
	}
	return false
}

// StartProxy forwards tailnet traffic to the local quark on [localPort].
// [localTLS] must match how the quark is actually serving that port — see
// serverutil.ServingTLS. Proxying plain HTTP at the TLS listener shows up as
// "TLS handshake error from 127.0.0.1" in the server log and fails every
// request.
func StartProxy(localPort int, localTLS bool) error {
	mu.Lock()
	defer mu.Unlock()
	if proxyLn != nil {
		return nil // already started
	}
	if srv == nil {
		return fmt.Errorf("tsnet not started")
	}
	ln, err := srv.Listen("tcp", ":80")
	if err != nil {
		return fmt.Errorf("tsnet listen failed: %w", err)
	}
	proxyLn = ln
	scheme := "http"
	if localTLS {
		scheme = "https"
	}
	target := &url.URL{
		Scheme: scheme,
		Host:   fmt.Sprintf("localhost:%d", localPort),
	}
	rp := newProxy(target, localTLS)
	go func() {
		if err := http.Serve(ln, rp); err != nil {
			log.Printf("[tsnet] proxy stopped: %v", err)
		}
	}()
	return nil
}

// EnsureStarted starts the tsnet node, re-provisioning if local state has been
// wiped. provisionFn is called only when no persisted state exists; it should
// return a fresh Headscale pre-auth key. The proxy is started against
// localPort after tsnet starts successfully; localTLS must match how the
// server is serving that port.
func EnsureStarted(localPort int, localTLS bool, provisionFn func() (string, error)) error {
	if IsRunning() {
		return nil
	}

	authKey := ""
	if !HasPersistedState() {
		log.Printf("[remote] no persisted tsnet state, re-provisioning...")
		key, err := provisionFn()
		if err != nil {
			return fmt.Errorf("re-provision: %w", err)
		}
		authKey = key
	}

	if err := Start(authKey); err != nil {
		return fmt.Errorf("start tsnet: %w", err)
	}

	if err := StartProxy(localPort, localTLS); err != nil {
		Stop()
		return fmt.Errorf("start proxy: %w", err)
	}

	return nil
}
