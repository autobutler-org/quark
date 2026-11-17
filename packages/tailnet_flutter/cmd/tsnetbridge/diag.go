// cspell:words tsnetbridge tailcfg rtts

package main

// Path diagnostics for remote access (#3883). Phone-to-Quark traffic goes
// either straight between the two, or through a public relay when they
// cannot punch through each other's NAT. Nothing showed which, so slow
// remote loads could not be explained. This file records it: the Quark
// peer's current path, every change between direct and relayed, ping times
// over the tunnel, and how long recent requests took. None of it holds a
// key, a token, a full address, or a file path (#3613).

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"math"
	"net"
	"net/netip"
	"strings"
	"sync"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/tailcfg"
	"tailscale.com/tsnet"
)

// The values of PeerPath.Path, the same words the Quark's report uses.
const (
	pathDirect    = "direct"
	pathRelay     = "relay"
	pathPeerRelay = "peer-relay"
	pathIdle      = "idle"
	pathUnknown   = "unknown"
)

// Bounds on what the bridge keeps. Both are rings: the oldest entry goes.
const (
	maxPathChanges = 32
	maxRequests    = 64
)

// pathWatchInterval is how often the bridge reads the Quark peer's path.
// Variable so a test can shorten it.
var pathWatchInterval = 5 * time.Second

// PeerPath is how traffic to the Quark travels right now.
type PeerPath struct {
	// Path is "direct", "relay", "peer-relay", "idle", or "unknown" when the
	// Quark is not among the node's peers.
	Path string `json:"path"`
	// Network is "lan" or "internet" for a direct path, by whether the
	// address is private. The address itself is never reported.
	Network string `json:"network,omitempty"`
	// RelayRegion is the relay region code, set when relayed. On an idle
	// path it is the region the Quark homes on.
	RelayRegion string `json:"relayRegion,omitempty"`
	// Online is whether the coordination server sees the Quark.
	Online bool `json:"online"`
	// LastHandshake is the last encrypted-session handshake with the Quark.
	LastHandshake time.Time `json:"lastHandshake,omitzero"`
	// RxBytes and TxBytes are what the phone received from and sent to the
	// Quark since the node started.
	RxBytes int64 `json:"rxBytes"`
	TxBytes int64 `json:"txBytes"`
}

// PathChange is one move of the Quark peer's path.
type PathChange struct {
	At time.Time `json:"at"`
	// Path is the new path, as describePath writes it: "direct (internet)",
	// "relay (nyc)".
	Path string `json:"path"`
}

// RequestTiming is one request the proxy carried.
type RequestTiming struct {
	// At is when the request reached the proxy.
	At time.Time `json:"at"`
	// Route is the first segment after /api/v0, such as "files" or
	// "thumbnails". The rest of the path names the user's files and stays out.
	Route  string `json:"route"`
	Status int    `json:"status"`
	// HeadersMs is the time to the Quark's response headers.
	HeadersMs float64 `json:"headersMs"`
	// BodyMs is the time until the last body byte was sent to the app.
	BodyMs float64 `json:"bodyMs"`
	// Bytes is the body size sent to the app.
	Bytes int64 `json:"bytes"`
}

// PeerStatusReport is what quark_tsnet_peer_status returns.
type PeerStatusReport struct {
	// State is the node's state, as in NodeStatus.
	State string `json:"state"`
	// Quark is the Quark peer's path, nil when there is no node.
	Quark *PeerPath `json:"quark"`
	// PathChanges lists the latest path changes, oldest first.
	PathChanges []PathChange `json:"pathChanges"`
	// Requests lists the latest requests, oldest first.
	Requests []RequestTiming `json:"requests"`
}

// PingStats summarizes one kind of ping.
type PingStats struct {
	// Sent and Received count the pings and their answers.
	Sent     int `json:"sent"`
	Received int `json:"received"`
	// MinMs and AvgMs are the round-trip times of the answered ones.
	MinMs float64 `json:"minMs"`
	AvgMs float64 `json:"avgMs"`
	// Path is how the last answer traveled. Set for the tunnel ping only;
	// a TCP connection does not say.
	Path string `json:"path,omitempty"`
	// Error is the last failure, empty when every ping was answered.
	Error string `json:"error,omitempty"`
}

// PingReport is what quark_tsnet_ping returns.
type PingReport struct {
	// Tunnel pings the Quark's node inside the encrypted tunnel; nil when
	// there is no node.
	Tunnel *PingStats `json:"tunnel"`
	// TCP opens a TCP connection to the Quark's address through the tunnel,
	// the same dial the proxy makes, and times the handshake.
	TCP PingStats `json:"tcp"`
}

var (
	diagMu      sync.Mutex
	pathChanges []PathChange
	requests    []RequestTiming
	lastPath    string
)

// resetDiag forgets the last node's history. Start calls it.
func resetDiag() {
	diagMu.Lock()
	defer diagMu.Unlock()
	pathChanges, requests, lastPath = nil, nil, ""
}

// recordPath appends a change when path differs from the last one seen. An
// idle or unknown path is not a change: the Quark keeps the path it had until
// traffic picks one again.
func recordPath(at time.Time, p PeerPath) {
	if p.Path == pathIdle || p.Path == pathUnknown {
		return
	}
	desc := describePath(p)
	diagMu.Lock()
	defer diagMu.Unlock()
	if desc == lastPath {
		return
	}
	lastPath = desc
	pathChanges = appendRing(pathChanges, PathChange{At: at, Path: desc}, maxPathChanges)
}

// recordRequest appends one request's timing.
func recordRequest(t RequestTiming) {
	diagMu.Lock()
	defer diagMu.Unlock()
	requests = appendRing(requests, t, maxRequests)
}

func appendRing[T any](s []T, v T, limit int) []T {
	s = append(s, v)
	if len(s) > limit {
		s = append(s[:0:0], s[len(s)-limit:]...)
	}
	return s
}

// describePath is a path in a few words: "direct (lan)", "relay (nyc)".
func describePath(p PeerPath) string {
	switch {
	case p.Path == pathDirect && p.Network != "":
		return p.Path + " (" + p.Network + ")"
	case p.Path == pathRelay && p.RelayRegion != "":
		return p.Path + " (" + p.RelayRegion + ")"
	default:
		return p.Path
	}
}

// peerPathFrom classifies one peer. CurAddr is set only while a direct path
// is in use. Relay is the region the peer homes on, which carries traffic
// when there is no direct path.
func peerPathFrom(ps *ipnstate.PeerStatus) PeerPath {
	if ps == nil {
		return PeerPath{Path: pathUnknown}
	}
	p := PeerPath{
		Online:        ps.Online,
		LastHandshake: ps.LastHandshake,
		RxBytes:       ps.RxBytes,
		TxBytes:       ps.TxBytes,
	}
	switch {
	case ps.CurAddr != "":
		p.Path, p.Network = pathDirect, addressNetwork(ps.CurAddr)
	case ps.PeerRelay != "":
		p.Path = pathPeerRelay
	case ps.Relay != "" && ps.Active:
		p.Path, p.RelayRegion = pathRelay, ps.Relay
	default:
		p.Path, p.RelayRegion = pathIdle, ps.Relay
	}
	return p
}

// addressNetwork is "lan" for a private address and "internet" for a public
// one. Only the class leaves this function.
func addressNetwork(addr string) string {
	ap, err := netip.ParseAddrPort(addr)
	if err != nil {
		return ""
	}
	ip := ap.Addr().Unmap()
	cgnat := netip.MustParsePrefix("100.64.0.0/10")
	if ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || cgnat.Contains(ip) {
		return "lan"
	}
	return "internet"
}

// pingPath is how a tunnel ping's answer traveled.
func pingPath(r *ipnstate.PingResult) string {
	switch {
	case r == nil:
		return ""
	case r.Endpoint != "":
		return describePath(PeerPath{Path: pathDirect, Network: addressNetwork(r.Endpoint)})
	case r.PeerRelay != "":
		return pathPeerRelay
	case r.DERPRegionCode != "":
		return describePath(PeerPath{Path: pathRelay, RelayRegion: r.DERPRegionCode})
	default:
		return pathUnknown
	}
}

// routeOf is the first path segment after /api/v0, or "other".
func routeOf(path string) string {
	rest, ok := strings.CutPrefix(path, "/api/v0/")
	if !ok {
		return "other"
	}
	seg, _, _ := strings.Cut(rest, "/")
	return cmp.Or(seg, "other")
}

// quarkPeer finds the peer that holds ip among st's peers.
func quarkPeer(st *ipnstate.Status, ip netip.Addr) *ipnstate.PeerStatus {
	if st == nil {
		return nil
	}
	for _, ps := range st.Peer {
		for _, a := range ps.TailscaleIPs {
			if a == ip {
				return ps
			}
		}
	}
	return nil
}

// upstreamIP is the tailnet address in upstream, for finding its peer.
func upstreamIP(upstream string) (netip.Addr, error) {
	u, err := parseUpstream(upstream)
	if err != nil {
		return netip.Addr{}, err
	}
	return netip.ParseAddr(u.Hostname())
}

// readQuarkPath reads the Quark peer's path from n.
func readQuarkPath(ctx context.Context, n *tsnet.Server, ip netip.Addr) (PeerPath, error) {
	lc, err := n.LocalClient()
	if err != nil {
		return PeerPath{}, err
	}
	st, err := lc.Status(ctx)
	if err != nil {
		return PeerPath{}, err
	}
	return peerPathFrom(quarkPeer(st, ip)), nil
}

// watchPath records the Quark peer's path while n is the running node.
func watchPath(n *tsnet.Server, ip netip.Addr) {
	tick := time.NewTicker(pathWatchInterval)
	defer tick.Stop()
	for range tick.C {
		mu.Lock()
		current := node == n
		mu.Unlock()
		if !current {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		p, err := readQuarkPath(ctx, n, ip)
		cancel()
		if err == nil {
			recordPath(time.Now(), p)
		}
	}
}

// PeerStatus is the Quark peer's path and the bridge's recent history.
func PeerStatus() PeerStatusReport {
	mu.Lock()
	n, up := node, upstream
	mu.Unlock()
	report := PeerStatusReport{State: Status().State}
	if n != nil {
		if ip, err := upstreamIP(up); err == nil {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			p, err := readQuarkPath(ctx, n, ip)
			cancel()
			if err == nil {
				recordPath(time.Now(), p)
				report.Quark = &p
			}
		}
	}
	diagMu.Lock()
	report.PathChanges = append([]PathChange{}, pathChanges...)
	report.Requests = append([]RequestTiming{}, requests...)
	diagMu.Unlock()
	return report
}

// Ping pings the Quark count times inside the tunnel, when there is a node,
// and opens count TCP connections to it through the tunnel.
func Ping(count int) PingReport {
	count = min(max(count, 1), 20)
	mu.Lock()
	n, up, dial := node, upstream, proxyDial
	mu.Unlock()
	var report PingReport
	if n != nil {
		report.Tunnel = tunnelPing(n, up, count)
	}
	report.TCP = tcpPing(dial, up, count)
	return report
}

func tunnelPing(n *tsnet.Server, up string, count int) *PingStats {
	stats := &PingStats{}
	ip, err := upstreamIP(up)
	if err != nil {
		stats.Error = err.Error()
		return stats
	}
	lc, err := n.LocalClient()
	if err != nil {
		stats.Error = err.Error()
		return stats
	}
	var rtts []time.Duration
	for range count {
		stats.Sent++
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		r, err := lc.Ping(ctx, ip, tailcfg.PingDisco)
		cancel()
		if err == nil && r.Err != "" {
			err = errors.New(r.Err)
		}
		if err != nil {
			stats.Error = err.Error()
			continue
		}
		rtts = append(rtts, time.Duration(r.LatencySeconds*float64(time.Second)))
		stats.Path = pingPath(r)
	}
	summarize(stats, rtts)
	return stats
}

func tcpPing(dial DialFunc, up string, count int) PingStats {
	stats := PingStats{}
	target, err := parseUpstream(up)
	if err != nil || dial == nil {
		stats.Error = "the proxy is not running"
		return stats
	}
	var rtts []time.Duration
	for range count {
		stats.Sent++
		ctx, cancel := context.WithTimeout(context.Background(), tunnelDialTimeout)
		start := time.Now()
		conn, err := dial(ctx, "tcp", target.Host)
		rtt := time.Since(start)
		cancel()
		if err != nil {
			stats.Error = redactDialError(err)
			continue
		}
		_ = conn.Close()
		rtts = append(rtts, rtt)
	}
	summarize(&stats, rtts)
	return stats
}

// redactDialError keeps whether a dial timed out or was refused, and drops
// the address a net.OpError names.
func redactDialError(err error) string {
	var ne net.Error
	switch {
	case errors.Is(err, context.DeadlineExceeded) || (errors.As(err, &ne) && ne.Timeout()):
		return "timeout"
	default:
		return "unreachable"
	}
}

func summarize(stats *PingStats, rtts []time.Duration) {
	stats.Received = len(rtts)
	if len(rtts) == 0 {
		return
	}
	lo, sum := time.Duration(math.MaxInt64), time.Duration(0)
	for _, d := range rtts {
		lo = min(lo, d)
		sum += d
	}
	stats.MinMs = ms(lo)
	stats.AvgMs = ms(sum / time.Duration(len(rtts)))
}

func ms(d time.Duration) float64 {
	return math.Round(float64(d.Microseconds())/10) / 100
}

func peerStatusJSON() string {
	b, err := json.Marshal(PeerStatus())
	if err != nil {
		return `{"state":"Stopped","quark":null,"pathChanges":[],"requests":[]}`
	}
	return string(b)
}

func pingJSON(count int) string {
	b, err := json.Marshal(Ping(count))
	if err != nil {
		return `{"tunnel":null,"tcp":{"sent":0,"received":0,"minMs":0,"avgMs":0,"error":"ping could not be encoded"}}`
	}
	return string(b)
}
