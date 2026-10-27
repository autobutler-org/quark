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
	"time"

	"tailscale.com/envknob"
	"tailscale.com/ipn"
	"tailscale.com/logtail"
	"tailscale.com/tsnet"
)

// upTimeout bounds how long Start waits for the node to reach Running.
const upTimeout = 60 * time.Second

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
	epoch++
	myEpoch := epoch
	mu.Unlock()

	dial := cfg.Dial
	var n *tsnet.Server
	var err error
	if dial == nil {
		n, dial, err = upNode(cfg)
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
	epoch++
	mu.Unlock()
	closePair(n, srv)
	return nil
}

// Status reports the node and the proxy port.
func Status() NodeStatus {
	mu.Lock()
	n, p, isStarting, errText := node, port, starting, lastErr
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

func upNode(cfg Config) (*tsnet.Server, DialFunc, error) {
	// The library uploads diagnostic logs and client metrics to its vendor
	// from the moment a node starts until the coordination server's first
	// map response, and for the life of the process if that response never
	// comes (#3786). Turn it off before a node exists. Phone builds also
	// pass ts_omit_logtail, which compiles the uploader out.
	logtail.Disable()
	envknob.SetNoLogsNoSupport()
	if cfg.StateDir == "" || cfg.ControlURL == "" || cfg.Hostname == "" {
		return nil, nil, errors.New("stateDir, controlUrl, and hostname are required")
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
	if _, err := srv.Up(ctx); err != nil {
		_ = srv.Close()
		return nil, nil, fmt.Errorf("joining the tailnet: %w", err)
	}
	// The same idea as `tailscale up --accept-dns=false`. Headscale pushes
	// override_local_dns. CorpDNSSet with CorpDNS left false turns that off.
	// There is no TUN here, so this does not touch the phone's resolver; it
	// keeps the node from applying the push if one ever could.
	lc, err := srv.LocalClient()
	if err == nil {
		prefsCtx, prefsCancel := context.WithTimeout(context.Background(), 10*time.Second)
		_, err = lc.EditPrefs(prefsCtx, &ipn.MaskedPrefs{CorpDNSSet: true})
		prefsCancel()
	}
	if err != nil {
		_ = srv.Close()
		return nil, nil, fmt.Errorf("turning off tailnet DNS: %w", err)
	}
	return srv, srv.Dial, nil
}

func closePair(n *tsnet.Server, srv *http.Server) {
	if srv != nil {
		_ = srv.Close()
	}
	if n != nil {
		_ = n.Close()
	}
}
