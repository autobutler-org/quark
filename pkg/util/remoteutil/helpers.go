package remoteutil

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/provisionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/tsnet"
)

// loginTimeout bounds how long superviseLogin waits for a node to either
// connect or ask for an interactive login. Running out means "not proven
// bad", so the node is left running.
const loginTimeout = time.Minute

// errReconnect is Status's error once superviseLogin has given up on a node.
var errReconnect = errors.New("couldn't reconnect to remote access; turn it off and on to try again")

// startLocked is Start's body. mu must be held.
func startLocked(authKey string) error {
	if running {
		return nil
	}
	dir := stateDir()
	if err := os.MkdirAll(dir, 0700); err != nil {
		lastErr = fmt.Errorf("failed to create tsnet state dir: %w", err)
		return lastErr
	}
	srv = &tsnet.Server{
		Hostname:   nodeHostname(provisionutil.DeviceID()),
		AuthKey:    authKey,
		Dir:        dir,
		ControlURL: controlURL(),
		Logf: func(format string, args ...any) {
			log.Printf("[tsnet] "+format, args...)
		},
		// Without this, tsnet sends its interactive login URL to plain
		// log.Printf, unprefixed (#2466).
		UserLogf: func(format string, args ...any) {
			log.Printf("[tsnet] "+format, args...)
		},
	}
	if err := srv.Start(); err != nil {
		srv = nil
		lastErr = fmt.Errorf("failed to start tsnet: %w", err)
		return lastErr
	}
	running = true
	lastErr = nil
	return nil
}

// startProxyLocked is StartProxy's body. mu must be held.
func startProxyLocked(localPort int, localTLS bool) error {
	if proxyLn != nil {
		return nil // already started
	}
	if srv == nil {
		lastErr = fmt.Errorf("tsnet not started")
		return lastErr
	}
	ln, err := srv.Listen("tcp", ":80")
	if err != nil {
		lastErr = fmt.Errorf("tsnet listen failed: %w", err)
		return lastErr
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
		srv := serverutil.NewHTTPServer(serverutil.NewHTTPServerParams{Handler: rp})
		if err := srv.Serve(ln); err != nil {
			log.Printf("[tsnet] proxy stopped: %v", err)
		}
	}()
	return nil
}

// stopLocked closes the proxy and the node. mu must be held.
func stopLocked() {
	if proxyLn != nil {
		proxyLn.Close()
		proxyLn = nil
	}
	if srv != nil {
		srv.Close()
		srv = nil
	}
	running = false
	stops++
}

// restartIfUnchanged is superviseLogin's re-enroll step. It starts the node
// and proxy with key, or records keyErr, but only if nothing has stopped or
// started a node since stopIfCurrent returned gen and remote access is still
// on. The check and the start share one hold of mu, so a Disable that lands
// while the key was being provisioned always wins. It reports whether it
// acted.
func restartIfUnchanged(gen uint64, key string, keyErr error, localPort int, localTLS bool) (bool, error) {
	// Read before taking mu: settingsutil does file I/O. Disable stops the
	// node before the setting is written, so stops is what closes the window;
	// the setting is a second guard.
	remoteOn := settingsutil.GetRemoteAccess()
	mu.Lock()
	defer mu.Unlock()
	if !remoteOn || stops != gen || srv != nil {
		return false, nil
	}
	if keyErr != nil {
		lastErr = fmt.Errorf("provision: %w", keyErr)
		return true, lastErr
	}
	if err := startLocked(key); err != nil {
		return true, fmt.Errorf("start tsnet: %w", err)
	}
	if err := startProxyLocked(localPort, localTLS); err != nil {
		stopLocked()
		return true, fmt.Errorf("start proxy: %w", err)
	}
	return true, nil
}

// ensureStarted is EnsureStarted's and Enable's body. With freshKey false,
// persisted state stands in for a key; with it true, a key is always
// provisioned, and superviseLogin never deletes the state dir, because that
// state holds the machine key Headscale knows the node by (#2469).
func ensureStarted(freshKey bool, localPort int, localTLS bool, provisionFn func() (string, error)) error {
	if IsRunning() {
		return nil
	}

	authKey := ""
	fromState := !freshKey && HasPersistedState()
	if !fromState {
		log.Printf("[remote] provisioning a key (fresh key requested: %v)", freshKey)
		key, err := provisionKey(provisionFn)
		if err != nil {
			return err
		}
		authKey = key
	}

	if err := startWithProxy(authKey, localPort, localTLS); err != nil {
		return err
	}
	go superviseLogin(fromState, localPort, localTLS, provisionFn)
	return nil
}

// provisionKey calls provisionFn, recording a failure for Status.
func provisionKey(provisionFn func() (string, error)) (string, error) {
	key, err := provisionFn()
	if err != nil {
		err = fmt.Errorf("provision: %w", err)
		mu.Lock()
		lastErr = err
		mu.Unlock()
		return "", err
	}
	return key, nil
}

// startWithProxy starts the node with authKey ("" reuses persisted state) and
// then its proxy, stopping the node again if the proxy cannot listen.
func startWithProxy(authKey string, localPort int, localTLS bool) error {
	if err := Start(authKey); err != nil {
		return fmt.Errorf("start tsnet: %w", err)
	}
	if err := StartProxy(localPort, localTLS); err != nil {
		Stop()
		return fmt.Errorf("start proxy: %w", err)
	}
	return nil
}

// currentServer is the running node, or nil.
func currentServer() *tsnet.Server {
	mu.Lock()
	defer mu.Unlock()
	return srv
}

// stopIfCurrent stops the node and records err for Status, but only if s is
// still the running node: a Disable or another start in the meantime wins.
// It returns the stop count after its own stop, for restartIfUnchanged.
func stopIfCurrent(s *tsnet.Server, err error) (uint64, bool) {
	mu.Lock()
	defer mu.Unlock()
	if s == nil || srv != s {
		return 0, false
	}
	stopLocked()
	lastErr = err
	return stops, true
}

// superviseLogin runs after EnsureStarted. A node that control asks to log in
// interactively would otherwise sit there forever, with tsnet logging the
// login URL every five seconds (#2466). If the node came from persisted
// state, that state is dead: delete it and enroll once more with a fresh key.
// If that node, or one started with a fresh key, is asked to log in too, stop
// it and leave Status an error that says what to do.
func superviseLogin(fromState bool, localPort int, localTLS bool, provisionFn func() (string, error)) {
	s := currentServer()
	if !waitForLoginPrompt(s) {
		return
	}
	if fromState {
		log.Printf("[remote] the tailnet rejected the saved enrollment, re-enrolling with a fresh key")
		gen, ok := stopIfCurrent(s, nil)
		if !ok {
			return
		}
		if err := os.RemoveAll(stateDir()); err != nil {
			mu.Lock()
			lastErr = fmt.Errorf("failed to remove tsnet state dir: %w", err)
			mu.Unlock()
			return
		}
		key, keyErr := provisionFn()
		acted, err := restartIfUnchanged(gen, key, keyErr, localPort, localTLS)
		if !acted {
			log.Printf("[remote] remote access was turned off during re-enroll, not restarting")
			return
		}
		if err != nil {
			log.Printf("[remote] re-enroll failed: %v", err)
			return
		}
		s = currentServer()
		if !waitForLoginPrompt(s) {
			return
		}
	}
	if _, ok := stopIfCurrent(s, errReconnect); ok {
		log.Printf("[remote] the tailnet still asks for an interactive login, stopping remote access")
	}
}

// waitForLoginPrompt polls s until it is Running (false), control asks it for
// an interactive login (true), it stops being the current node (false), or
// loginTimeout passes (false).
func waitForLoginPrompt(s *tsnet.Server) bool {
	if s == nil {
		return false
	}
	lc, err := s.LocalClient()
	if err != nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), loginTimeout)
	defer cancel()
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	for {
		if currentServer() != s {
			return false
		}
		if st, err := lc.StatusWithoutPeers(ctx); err == nil {
			if st.BackendState == ipn.Running.String() {
				return false
			}
			if needsInteractiveLogin(st) {
				return true
			}
		}
		select {
		case <-ctx.Done():
			return false
		case <-tick.C:
		}
	}
}

// needsInteractiveLogin reports whether control has asked the node for a
// human login: NeedsLogin with an auth URL. NeedsLogin alone is not enough. A
// node with no saved key enters NeedsLogin before it presents a pre-auth key
// and stays there until its first network map, with no auth URL, even when the key
// is good (tailscale.com LocalBackend.startLocked skips cc.Login without a
// node key, and nextStateLocked keeps NeedsLogin until a network map arrives).
func needsInteractiveLogin(st *ipnstate.Status) bool {
	return st != nil && st.BackendState == ipn.NeedsLogin.String() && st.AuthURL != ""
}

// newProxy builds the reverse proxy that carries tailnet traffic to the quark
// serving on target.
func newProxy(target *url.URL, localTLS bool) *httputil.ReverseProxy {
	rp := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(target)
			r.Out.Host = target.Host
			// Rewrite strips inbound forwarding headers; without this every
			// tailnet peer reaches the quark as 127.0.0.1 and they all share
			// one login rate-limit bucket.
			r.SetXForwarded()
		},
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.MaxIdleConnsPerHost = proxyMaxIdleConnsPerHost
	if localTLS {
		// The quark presents its own self-signed cert, and this hop is a
		// loopback connection to that same process — there is no third party to
		// authenticate, and no CA that could vouch for the cert.
		transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
	}
	rp.Transport = transport
	return rp
}

// proxyMaxIdleConnsPerHost is how many idle loopback connections the proxy
// keeps to the quark. The default of 2 made every request past the second in
// flight open a new connection, over TLS a full handshake each (#2755).
const proxyMaxIdleConnsPerHost = 32

// connectionFromStatus maps a tsnet status to whether the node is on the
// tailnet and, if it is, the URL peers reach it at. tsnet.Server.Start returns
// before the node authenticates, so only BackendState "Running" counts —
// "Starting", "NeedsLogin" and the rest are not connected, whatever IP the
// node may already hold.
//
// "NeedsLogin" with an auth URL is a failure: login cannot continue without a
// human (#1876), which for a node given a pre-auth key means control rejected
// the key or it expired. Without an auth URL it is the brief wait before a
// fresh key's first network map, and counts as connecting.
func connectionFromStatus(st *ipnstate.Status) StatusResult {
	if st == nil {
		return StatusResult{}
	}
	switch st.BackendState {
	case ipn.Running.String():
		if len(st.TailscaleIPs) == 0 {
			return StatusResult{Connected: true}
		}
		return StatusResult{Connected: true, RemoteURL: fmt.Sprintf("http://%s:80", st.TailscaleIPs[0])}
	case ipn.NeedsLogin.String():
		// A fresh pre-auth key also sits in NeedsLogin until its first network
		// map; only an auth URL means control wants a human.
		if needsInteractiveLogin(st) {
			return StatusResult{Error: errKeyRejected}
		}
		return StatusResult{}
	default:
		return StatusResult{}
	}
}

// nodeHostname is the tsnet hostname for the Quark with deviceID:
// "quark-" and the first eight hex digits of the ID. It is stable across
// restarts and distinct per device, so Headscale and MagicDNS can tell one
// Quark from another (#2358, #1880) instead of suffixing a shared "quark".
func nodeHostname(deviceID string) string {
	return "quark-" + deviceID[:min(8, len(deviceID))]
}

// newPairDeviceID is a random ID for one paired device, which the
// provisioning service logs and rate-limits the key against.
func newPairDeviceID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate device id: %w", err)
	}
	return "pair-" + hex.EncodeToString(b), nil
}

func controlURL() string {
	u := os.Getenv("QUARK_HEADSCALE_URL")
	if u == "" {
		u = defaultControlURL
	}
	if strings.HasPrefix(u, "http://") {
		log.Printf("[remote] WARNING: Headscale control URL is using HTTP (%s). Auth keys will be sent in plaintext. Use HTTPS in production.", u)
	}
	return u
}

// stateDir returns the path where tsnet should persist its state. On Linux it
// prefers the system service directory if the parent exists; otherwise it falls
// back to the user's home config directory. Directory creation is left to the
// caller (Start).
func stateDir() string {
	if runtime.GOOS == "linux" {
		svcDir := "/var/lib/quark/tsnet"
		if _, err := os.Stat(filepath.Dir(svcDir)); err == nil {
			return svcDir
		}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		home = os.TempDir()
	}
	return filepath.Join(home, ".config", "quark", "tsnet")
}
