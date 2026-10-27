// cspell:words CorpDNS loopback tsnetbridge userspace

// Command tsnetbridge is the C library the iOS and Android app loads (#1881).
//
// quark_tsnet_start joins a userspace tailnet node and serves a plain HTTP
// reverse proxy on 127.0.0.1. The proxy dials the Quark with tsnet.Server.Dial.
// The app points its remote address at that proxy. The node never calls
// Listen, so nothing on the tailnet can reach into the phone, and it does not
// use Server.Loopback, which speaks SOCKS5 only.
//
// There is one node per process. The Dart side calls start, stop, and status
// one at a time; the mutex here still makes a second start fail cleanly.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"tailscale.com/envknob"
	"tailscale.com/ipn"
	"tailscale.com/logtail"
	"tailscale.com/tsnet"
)

// upTimeout bounds how long Start waits for the node to reach Running.
const upTimeout = 60 * time.Second

// needsLogin is the backend state of a node with no key the coordination
// server accepts.
const needsLogin = "NeedsLogin"

// errNeedsLogin ends a start with no key once the node reaches NeedsLogin.
var errNeedsLogin = errors.New("the coordination server did not accept this node; it needs a new key")

// DialFunc dials the Quark. Tests inject one so they never join a tailnet.
// Production uses tsnet.Server.Dial.
type DialFunc func(ctx context.Context, network, addr string) (net.Conn, error)

// Config is everything Start needs. Dial, when set, skips the tailnet and
// serves the proxy with that dial.
type Config struct {
	StateDir   string
	ControlURL string
	AuthKey    string
	Hostname   string
	Upstream   string
	Dial       DialFunc
}

// NodeStatus is the JSON quark_tsnet_status returns.
type NodeStatus struct {
	// State is "Stopped", "Starting", "Running", or another backend state.
	// After a start that ended in NeedsLogin it stays NeedsLogin until the
	// next start or stop.
	State string `json:"state"`
	// TailnetIPs are this node's own tailnet addresses. Empty when the
	// proxy is running on an injected dial, which has no node.
	TailnetIPs []string `json:"tailnetIPs"`
	// Port is the loopback proxy port, 0 when it is not listening. The token
	// the proxy asks for is not here; quark_tsnet_token returns it.
	Port int `json:"port"`
	// Error is the last start failure, empty after a successful start.
	Error string `json:"error"`
}

var (
	mu       sync.Mutex
	node     *tsnet.Server
	proxy    *http.Server
	port     int
	token    string
	starting bool
	lastErr  string
	// failedState is the backend state a failed start ended in, so Status
	// reports NeedsLogin rather than Stopped after a rejected key.
	failedState string
	// epoch bumps on Stop so a start that loses the race closes what it opened.
	epoch uint64
)

// Start joins the tailnet, unless Config.Dial is set, and serves the proxy.
// It returns the proxy port and the token every request must carry in
// TokenHeader. A second start without a stop fails.
func Start(cfg Config) (int, string, error) {
	mu.Lock()
	if node != nil || proxy != nil || starting {
		mu.Unlock()
		return 0, "", errors.New("tsnet bridge is already running; stop it first")
	}
	starting = true
	lastErr = ""
	failedState = ""
	epoch++
	myEpoch := epoch
	mu.Unlock()

	dial := cfg.Dial
	var n *tsnet.Server
	var state string
	var err error
	if dial == nil {
		n, dial, state, err = upNode(cfg)
	}
	var srv *http.Server
	var p int
	var tok string
	if err == nil {
		p, tok, srv, err = serveProxy(cfg.Upstream, dial)
	}

	mu.Lock()
	defer mu.Unlock()
	if epoch != myEpoch {
		closePair(n, srv)
		starting = false
		return 0, "", errors.New("tsnet bridge stopped before it finished starting")
	}
	starting = false
	if err != nil {
		closePair(n, srv)
		lastErr = err.Error()
		failedState = state
		return 0, "", err
	}
	node, proxy, port, token = n, srv, p, tok
	return p, tok, nil
}

// Token is the running proxy's token, empty when it is stopped.
func Token() string {
	mu.Lock()
	defer mu.Unlock()
	return token
}

// Stop shuts the proxy and the node down. Stopping a stopped bridge is a no-op.
func Stop() error {
	mu.Lock()
	n, srv := node, proxy
	node, proxy, port, token = nil, nil, 0, ""
	failedState = ""
	epoch++
	mu.Unlock()
	closePair(n, srv)
	return nil
}

// Status reports the node and the proxy port.
func Status() NodeStatus {
	mu.Lock()
	n, p, isStarting, errText, failed := node, port, starting, lastErr, failedState
	running := proxy != nil
	mu.Unlock()

	st := NodeStatus{State: "Stopped", TailnetIPs: []string{}, Port: p, Error: errText}
	if isStarting {
		st.State = "Starting"
		return st
	}
	if n == nil {
		if running {
			st.State = "Running"
		} else if failed == needsLogin {
			st.State = needsLogin
		}
		return st
	}
	lc, err := n.LocalClient()
	if err != nil {
		st.Error = err.Error()
		return st
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	got, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		st.Error = err.Error()
		return st
	}
	st.State = got.BackendState
	for _, ip := range got.TailscaleIPs {
		st.TailnetIPs = append(st.TailnetIPs, ip.String())
	}
	return st
}

// statusJSON is what the C API returns. It never returns an empty pointer.
func statusJSON() string {
	b, err := json.Marshal(Status())
	if err != nil {
		return `{"state":"Stopped","tailnetIPs":[],"port":0,"error":"status could not be encoded"}`
	}
	return string(b)
}

// upNode joins the tailnet. When it fails, it also returns the last backend
// state the node reported.
func upNode(cfg Config) (*tsnet.Server, DialFunc, string, error) {
	// tsnet uploads its diagnostic logs and metrics to the library vendor's
	// log host until our coordination server's first map response says
	// stop. Turn that off for the process before a node exists (#3786).
	logtail.Disable()
	envknob.SetNoLogsNoSupport()
	if cfg.StateDir == "" || cfg.ControlURL == "" || cfg.Hostname == "" {
		return nil, nil, "", errors.New("stateDir, controlUrl, and hostname are required")
	}
	silent := func(string, ...any) {}
	srv := &tsnet.Server{
		Dir:        cfg.StateDir,
		ControlURL: cfg.ControlURL,
		AuthKey:    cfg.AuthKey,
		Hostname:   cfg.Hostname,
		Logf:       silent,
		UserLogf:   silent,
	}
	ctx, cancel := context.WithTimeout(context.Background(), upTimeout)
	defer cancel()
	lc, err := srv.LocalClient()
	if err != nil {
		_ = srv.Close()
		return nil, nil, "", fmt.Errorf("starting the node: %w", err)
	}
	upCtx, stopUp := context.WithCancelCause(ctx)
	defer stopUp(nil)
	// Up waits for Running and nothing else. A node with no key the
	// coordination server accepts sits in NeedsLogin until the timeout, so
	// this watches for that and keeps the last state for Status (#3783).
	var state atomic.Int64
	watcher, err := lc.WatchIPNBus(upCtx, ipn.NotifyInitialState)
	if err == nil {
		go func() {
			defer watcher.Close()
			for {
				n, err := watcher.Next()
				if err != nil {
					return
				}
				if n.State == nil {
					continue
				}
				state.Store(int64(*n.State))
				if *n.State == ipn.NeedsLogin && cfg.AuthKey == "" {
					stopUp(errNeedsLogin)
					return
				}
			}
		}()
	}
	if _, err := srv.Up(upCtx); err != nil {
		_ = srv.Close()
		if cause := context.Cause(upCtx); errors.Is(cause, errNeedsLogin) {
			err = cause
		}
		return nil, nil, ipn.State(state.Load()).String(), fmt.Errorf("joining the tailnet: %w", err)
	}
	// The same idea as `tailscale up --accept-dns=false`. Headscale pushes
	// override_local_dns. CorpDNSSet with CorpDNS left false turns that off.
	// There is no TUN here, so this does not touch the phone's resolver; it
	// keeps the node from applying the push if one ever could.
	if err == nil {
		prefsCtx, prefsCancel := context.WithTimeout(context.Background(), 10*time.Second)
		_, err = lc.EditPrefs(prefsCtx, &ipn.MaskedPrefs{CorpDNSSet: true})
		prefsCancel()
	}
	if err != nil {
		_ = srv.Close()
		return nil, nil, "", fmt.Errorf("turning off tailnet DNS: %w", err)
	}
	return srv, srv.Dial, "", nil
}

func closePair(n *tsnet.Server, srv *http.Server) {
	if srv != nil {
		_ = srv.Close()
	}
	if n != nil {
		_ = n.Close()
	}
}
