// Package bridge runs a userspace tsnet node inside the Quark app and puts a
// plain-HTTP reverse proxy on 127.0.0.1 in front of one Quark on the tailnet
// (#1881).
//
// The app's HTTP client, the native media players and the image cache all
// talk to the loopback URL; the proxy carries each connection over the
// tailnet with [tsnet.Server.Dial]. That is why this is not
// [tsnet.Server.Loopback]: Loopback serves SOCKS5 only, and Dart's HttpClient
// cannot speak SOCKS5.
//
// The node never calls [tsnet.Server.Listen]. A phone only dials its Quark
// (#2320): nothing on the tailnet may reach into the app, so there is no
// listener to expose.
//
// There is exactly one node per process, so the package keeps it in a
// package-level variable guarded by a mutex; the cgo exports in the parent
// package are thin wrappers over [Start], [Stop] and [CurrentStatus].
package bridge

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"sync"
	"time"

	"tailscale.com/ipn"
	"tailscale.com/tsnet"
)

// Config is everything [Start] needs to join the tailnet and reach the Quark.
type Config struct {
	// StateDir holds the node's key and state, so a restart rejoins without
	// spending another single-use auth key.
	StateDir string
	// ControlURL is the Headscale coordination server.
	ControlURL string
	// AuthKey is the pre-auth key. It is ignored once StateDir holds a node
	// that has already logged in.
	AuthKey string
	// Hostname is this device's name on the tailnet.
	Hostname string
	// Upstream is the Quark's tailnet address: `http://100.x.y.z`,
	// `http://100.x.y.z:80`, or a bare `100.x.y.z[:port]`.
	Upstream string
	// Logf receives tsnet's backend logs. Nil discards them.
	Logf func(format string, args ...any)
}

// Status is the JSON the app polls.
type Status struct {
	// State is "Stopped", "Starting", or tailscale's backend state
	// ("Running", "NeedsLogin", "Starting", ...).
	State string `json:"state"`
	// TailnetIPs are this node's own tailnet addresses.
	TailnetIPs []string `json:"tailnetIPs"`
	// Port is the loopback proxy port, 0 when not running.
	Port int `json:"port"`
	// Error is the last start failure, empty after a successful start.
	Error string `json:"error"`
}

// upTimeout bounds how long [Start] waits for the node to reach Running.
const upTimeout = 60 * time.Second

// ponytail: one node per process in a package var; a handle-based API if
// the app ever needs two tailnets at once.
var (
	mu       sync.Mutex
	node     *tsnet.Server
	proxy    *http.Server
	port     int
	starting bool
	lastErr  string
)

// Start joins the tailnet and starts the loopback proxy, returning its port.
// It blocks until the node is Running or [upTimeout] passes.
func Start(cfg Config) (int, error) {
	mu.Lock()
	if node != nil || starting {
		mu.Unlock()
		return 0, errors.New("tsnet bridge is already running; stop it first")
	}
	starting = true
	lastErr = ""
	mu.Unlock()

	srv, p, rp, err := start(cfg)

	mu.Lock()
	defer mu.Unlock()
	starting = false
	if err != nil {
		lastErr = err.Error()
		return 0, err
	}
	node, proxy, port = srv, rp, p
	return p, nil
}

func start(cfg Config) (*tsnet.Server, int, *http.Server, error) {
	target, err := parseUpstream(cfg.Upstream)
	if err != nil {
		return nil, 0, nil, err
	}
	logf := cfg.Logf
	if logf == nil {
		logf = func(string, ...any) {}
	}
	srv := &tsnet.Server{
		Dir:        cfg.StateDir,
		ControlURL: cfg.ControlURL,
		AuthKey:    cfg.AuthKey,
		Hostname:   cfg.Hostname,
		Logf:       logf,
		UserLogf:   logf,
	}
	ctx, cancel := context.WithTimeout(context.Background(), upTimeout)
	defer cancel()
	if _, err := srv.Up(ctx); err != nil {
		_ = srv.Close()
		return nil, 0, nil, fmt.Errorf("joining the tailnet: %w", err)
	}
	// The equivalent of `tailscale up --accept-dns=false`. With no TUN the
	// node has no OS DNS configurator to touch anyway, but Headscale pushes
	// `override_local_dns`, so turn it off explicitly rather than rely on that.
	lc, err := srv.LocalClient()
	if err == nil {
		_, err = lc.EditPrefs(ctx, &ipn.MaskedPrefs{CorpDNSSet: true})
	}
	if err != nil {
		_ = srv.Close()
		return nil, 0, nil, fmt.Errorf("turning off tailnet DNS: %w", err)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		_ = srv.Close()
		return nil, 0, nil, fmt.Errorf("opening the loopback proxy: %w", err)
	}
	rp := &http.Server{Handler: newProxy(target, srv.Dial), ReadHeaderTimeout: 10 * time.Second}
	go func() { _ = rp.Serve(ln) }()
	return srv, ln.Addr().(*net.TCPAddr).Port, rp, nil
}

// newProxy forwards every request to target over dial. Bodies are streamed
// in both directions and headers, Range included, pass through untouched, so
// video seeks become range requests against the Quark and nothing is
// buffered. FlushInterval -1 flushes each write, which keeps SSE and
// progressive media moving.
func newProxy(target *url.URL, dial func(ctx context.Context, network, addr string) (net.Conn, error)) http.Handler {
	return &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(target)
		},
		Transport: &http.Transport{
			DialContext:         dial,
			MaxIdleConnsPerHost: 8,
			IdleConnTimeout:     90 * time.Second,
		},
		FlushInterval: -1,
	}
}

func parseUpstream(s string) (*url.URL, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, errors.New("upstream is empty; pass the Quark's tailnet address, e.g. http://100.64.0.1")
	}
	if !strings.Contains(s, "://") {
		s = "http://" + s
	}
	u, err := url.Parse(s)
	if err != nil || u.Host == "" {
		return nil, fmt.Errorf("upstream %q is not an address like http://100.64.0.1", s)
	}
	if u.Scheme != "http" {
		return nil, fmt.Errorf("upstream scheme %q unsupported: the Quark serves plain HTTP on the tailnet", u.Scheme)
	}
	if u.Port() == "" {
		u.Host = net.JoinHostPort(u.Hostname(), "80")
	}
	return &url.URL{Scheme: u.Scheme, Host: u.Host}, nil
}

// Stop shuts the proxy and the node down. Stopping a stopped bridge is a
// no-op.
func Stop() error {
	mu.Lock()
	srv, rp := node, proxy
	node, proxy, port = nil, nil, 0
	mu.Unlock()
	if srv == nil {
		return nil
	}
	_ = rp.Close()
	return srv.Close()
}

// CurrentStatus reports the node's state for the app to poll.
func CurrentStatus() Status {
	mu.Lock()
	srv, p, isStarting, errText := node, port, starting, lastErr
	mu.Unlock()
	st := Status{State: "Stopped", TailnetIPs: []string{}, Port: p, Error: errText}
	if isStarting {
		st.State = "Starting"
	}
	if srv == nil {
		return st
	}
	lc, err := srv.LocalClient()
	if err != nil {
		st.Error = err.Error()
		return st
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	s, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		st.Error = err.Error()
		return st
	}
	st.State = s.BackendState
	for _, ip := range s.TailscaleIPs {
		st.TailnetIPs = append(st.TailnetIPs, ip.String())
	}
	return st
}
