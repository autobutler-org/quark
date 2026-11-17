package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"strings"
	"testing"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/netcheck"
	"tailscale.com/types/key"
	"tailscale.com/types/opt"
)

// TestPeerPathFrom pins how the Quark peer's status maps to a path (#3883).
func TestPeerPathFrom(t *testing.T) {
	cases := []struct {
		name string
		ps   *ipnstate.PeerStatus
		want PeerPath
	}{
		{"not a peer", nil, PeerPath{Path: pathUnknown}},
		{"direct at home", &ipnstate.PeerStatus{CurAddr: "192.168.1.5:41641", Relay: "nyc", Active: true},
			PeerPath{Path: pathDirect, Network: "lan"}},
		{"direct away", &ipnstate.PeerStatus{CurAddr: "198.51.100.1:41641", Relay: "nyc", Active: true},
			PeerPath{Path: pathDirect, Network: "internet"}},
		{"relayed", &ipnstate.PeerStatus{Relay: "nyc", Active: true}, PeerPath{Path: pathRelay, RelayRegion: "nyc"}},
		{"peer relay", &ipnstate.PeerStatus{PeerRelay: "x", Active: true}, PeerPath{Path: pathPeerRelay}},
		{"idle", &ipnstate.PeerStatus{Relay: "nyc"}, PeerPath{Path: pathIdle, RelayRegion: "nyc"}},
	}
	for _, tc := range cases {
		if got := peerPathFrom(tc.ps); got != tc.want {
			t.Errorf("%s: peerPathFrom = %+v; want %+v", tc.name, got, tc.want)
		}
	}
}

// TestQuarkPeer finds the Quark among the node's peers by its address.
func TestQuarkPeer(t *testing.T) {
	quark := &ipnstate.PeerStatus{OS: "linux", TailscaleIPs: []netip.Addr{netip.MustParseAddr("100.64.0.1")}}
	other := &ipnstate.PeerStatus{OS: "iOS", TailscaleIPs: []netip.Addr{netip.MustParseAddr("100.64.0.9")}}
	st := &ipnstate.Status{Peer: map[key.NodePublic]*ipnstate.PeerStatus{
		key.NewNode().Public(): other,
		key.NewNode().Public(): quark,
	}}
	ip, err := upstreamIP("http://100.64.0.1")
	if err != nil {
		t.Fatal(err)
	}
	if got := quarkPeer(st, ip); got != quark {
		t.Errorf("quarkPeer = %+v; want the Quark", got)
	}
	if got := quarkPeer(st, netip.MustParseAddr("100.64.0.2")); got != nil {
		t.Errorf("quarkPeer for an unknown address = %+v; want nil", got)
	}
}

// TestPingPath names how a tunnel ping traveled without its address.
func TestPingPath(t *testing.T) {
	for _, tc := range []struct {
		r    *ipnstate.PingResult
		want string
	}{
		{&ipnstate.PingResult{Endpoint: "203.0.113.4:41641"}, "direct (internet)"},
		{&ipnstate.PingResult{Endpoint: "10.0.0.4:41641"}, "direct (lan)"},
		{&ipnstate.PingResult{DERPRegionID: 1, DERPRegionCode: "nyc"}, "relay (nyc)"},
		{&ipnstate.PingResult{PeerRelay: "x"}, pathPeerRelay},
		{&ipnstate.PingResult{}, pathUnknown},
	} {
		if got := pingPath(tc.r); got != tc.want {
			t.Errorf("pingPath(%+v) = %q; want %q", tc.r, got, tc.want)
		}
	}
}

// TestRecordPath_ChangesOnly keeps one entry per change between direct and
// relayed, skips idle readings, and keeps only the latest maxPathChanges.
func TestRecordPath_ChangesOnly(t *testing.T) {
	resetDiag()
	t.Cleanup(resetDiag)
	at := time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC)
	relay := PeerPath{Path: pathRelay, RelayRegion: "nyc"}
	direct := PeerPath{Path: pathDirect, Network: "internet"}
	for _, p := range []PeerPath{relay, relay, {Path: pathIdle}, direct, direct, {Path: pathUnknown}, relay} {
		recordPath(at, p)
	}
	got := PeerStatus().PathChanges
	want := []string{"relay (nyc)", "direct (internet)", "relay (nyc)"}
	if len(got) != len(want) {
		t.Fatalf("path changes = %+v; want %v", got, want)
	}
	for i := range want {
		if got[i].Path != want[i] || !got[i].At.Equal(at) {
			t.Errorf("change %d = %+v; want %q at %v", i, got[i], want[i], at)
		}
	}

	for i := range maxPathChanges + 5 {
		recordPath(at, PeerPath{Path: pathRelay, RelayRegion: string(rune('a' + i%2))})
	}
	if n := len(PeerStatus().PathChanges); n != maxPathChanges {
		t.Errorf("kept %d path changes; want %d", n, maxPathChanges)
	}
}

// TestRouteOf keeps only the first segment after /api/v0, so a request log
// never holds a file name.
func TestRouteOf(t *testing.T) {
	for path, want := range map[string]string{
		"/api/v0/files/Photos/beach.jpg": "files",
		"/api/v0/thumbnails":             "thumbnails",
		"/api/v0/":                       "other",
		"/index.html":                    "other",
	} {
		if got := routeOf(path); got != want {
			t.Errorf("routeOf(%q) = %q; want %q", path, got, want)
		}
	}
}

// TestProxy_RecordsRequestTimings times each request the proxy carries, to
// headers and to the end of the body, and records failures too. It holds
// the route and never the rest of the path.
func TestProxy_RecordsRequestTimings(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "hello")
	}))
	t.Cleanup(backend.Close)
	port, token, err := Start(Config{
		Upstream: "http://100.64.0.1",
		Dial: func(context.Context, string, string) (net.Conn, error) {
			return net.Dial("tcp", backend.Listener.Addr().String())
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = Stop() })

	resp, _ := proxyGet(t, port, token)
	if _, err := io.Copy(io.Discard, resp.Body); err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()

	var reqs []RequestTiming
	for deadline := time.Now().Add(2 * time.Second); time.Now().Before(deadline); time.Sleep(10 * time.Millisecond) {
		if reqs = PeerStatus().Requests; len(reqs) > 0 {
			break
		}
	}
	if len(reqs) != 1 {
		t.Fatalf("requests = %+v; want one", reqs)
	}
	r := reqs[0]
	if r.Route != "files" || r.Status != http.StatusOK || r.Bytes != 5 || r.BodyMs < r.HeadersMs || r.At.IsZero() {
		t.Errorf("timing = %+v; want files, 200, 5 bytes, body after headers", r)
	}

	st := PeerStatus()
	if st.State != "Running" || st.Quark != nil {
		t.Errorf("peer status = %+v; want Running with no Quark peer on an injected dial", st)
	}
	b, err := json.Marshal(st)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(b), token) || strings.Contains(string(b), "100.64.0.1") {
		t.Errorf("peer status %s holds the token or the Quark's address", b)
	}
}

// TestPing_TCPThroughInjectedDial times TCP connections through the proxy's
// dial, and reports a failed dial without its address.
func TestPing_TCPThroughInjectedDial(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			c.Close()
		}
	}()
	var dialed []string
	_, _, err = Start(Config{
		Upstream: "http://100.64.0.1",
		Dial: func(_ context.Context, _, addr string) (net.Conn, error) {
			dialed = append(dialed, addr)
			return net.Dial("tcp", ln.Addr().String())
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	got := Ping(3)
	_ = Stop()
	if got.Tunnel != nil {
		t.Errorf("tunnel ping = %+v; want none without a node", got.Tunnel)
	}
	if got.TCP.Sent != 3 || got.TCP.Received != 3 || got.TCP.Error != "" || got.TCP.AvgMs < got.TCP.MinMs {
		t.Errorf("tcp ping = %+v; want three answered", got.TCP)
	}
	for _, a := range dialed {
		if a != "100.64.0.1:80" {
			t.Errorf("dialed %q; want the Quark's tailnet address", a)
		}
	}

	_, _, err = Start(Config{
		Upstream: "http://100.64.0.1",
		Dial: func(context.Context, string, string) (net.Conn, error) {
			return nil, &net.OpError{Op: "dial", Net: "tcp", Err: errors.New("refused 100.64.0.1:80")}
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = Stop() })
	failed := Ping(1)
	if failed.TCP.Received != 0 || failed.TCP.Error != "unreachable" {
		t.Errorf("failed tcp ping = %+v; want unreachable with no address", failed.TCP)
	}
}

// TestPing_Stopped reports a stopped proxy instead of dialing.
func TestPing_Stopped(t *testing.T) {
	got := Ping(2)
	if got.Tunnel != nil || got.TCP.Sent != 0 || got.TCP.Error == "" {
		t.Errorf("ping while stopped = %+v; want no pings and an error", got)
	}
	var decoded PingReport
	if err := json.Unmarshal([]byte(pingJSON(2)), &decoded); err != nil {
		t.Errorf("pingJSON is not JSON: %v", err)
	}
}

// TestNetworkCheckFrom summarizes the phone's network check without the
// public address it found.
func TestNetworkCheckFrom(t *testing.T) {
	if networkCheckFrom(nil) != nil {
		t.Error("networkCheckFrom(nil) is not nil")
	}
	r := &netcheck.Report{
		UDP:                   true,
		MappingVariesByDestIP: opt.NewBool(true),
		PMP:                   opt.NewBool(false),
		PreferredDERP:         1,
		RegionLatency:         netcheck.RegionLatency{1: 40 * time.Millisecond},
		GlobalV4:              netip.MustParseAddrPort("203.0.113.8:1234"),
	}
	got := networkCheckFrom(r)
	want := NetworkCheck{UDP: true, MappingVariesByDestination: "yes", UPnP: "unknown", NATPMP: "no", PCP: "unknown", PreferredRelayLatencyMs: 40}
	if got == nil || *got != want {
		t.Fatalf("networkCheckFrom = %+v; want %+v", got, want)
	}
	b, err := json.Marshal(got)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(b), "203.0.113.8") {
		t.Errorf("network check %s holds the public address", b)
	}
}
