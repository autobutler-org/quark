// cspell:words netcheck natpmp cgnat upnp

package remoteutil

import (
	"cmp"
	"context"
	"fmt"
	"log"
	"net/netip"
	"slices"
	"strings"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/netcheck"
	"tailscale.com/tsnet"
	"tailscale.com/types/key"
	"tailscale.com/types/opt"
)

// pathWatchInterval is how often watchPaths reads the node's peers. A path
// upgrade from relay to direct usually lands within seconds of traffic, so
// this catches each change without costing anything noticeable.
const pathWatchInterval = 15 * time.Second

// pathReport is PathReport for the node s.
func pathReport(ctx context.Context, s *tsnet.Server) (PathReportResult, error) {
	lc, err := s.LocalClient()
	if err != nil {
		return PathReportResult{Peers: []PeerPath{}}, err
	}
	st, err := lc.Status(ctx)
	if err != nil {
		return PathReportResult{Peers: []PeerPath{}}, err
	}
	result := PathReportResult{
		Connected: connectionFromStatus(st).Connected,
		Network:   networkCheckFrom(lastNetcheck(ctx, s), st),
		Peers:     peerPathsFrom(st),
	}
	return result, nil
}

// lastNetcheck is the node's most recent network check, nil before the first.
func lastNetcheck(ctx context.Context, s *tsnet.Server) *netcheck.Report {
	sys := s.Sys()
	if sys == nil {
		return nil
	}
	conn, ok := sys.MagicSock.GetOK()
	if !ok || conn == nil {
		return nil
	}
	return conn.GetLastNetcheckReport(ctx)
}

// refreshNetcheck asks s's node for a new network check and waits up to
// timeout for it to land.
func refreshNetcheck(s *tsnet.Server, timeout time.Duration) {
	sys := s.Sys()
	if sys == nil {
		return
	}
	conn, ok := sys.MagicSock.GetOK()
	if !ok || conn == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	awaitFreshNetcheck(ctx, conn.GetLastNetcheckReport, func() { conn.ReSTUN("remote-access path report") }, netcheckPollInterval)
}

// netcheckPollInterval is how often awaitFreshNetcheck looks for the check it
// asked for.
const netcheckPollInterval = 200 * time.Millisecond

// awaitFreshNetcheck notes the last check's time, calls trigger, and polls
// last until a check newer than that lands or ctx ends. It returns the newest
// check it saw, which is the old one (or nil) when the new one never landed.
func awaitFreshNetcheck(ctx context.Context, last func(context.Context) *netcheck.Report, trigger func(), every time.Duration) *netcheck.Report {
	before := last(ctx)
	var since time.Time
	if before != nil {
		since = before.Now
	}
	trigger()
	tick := time.NewTicker(every)
	defer tick.Stop()
	for {
		if r := last(ctx); r != nil && r.Now.After(since) {
			return r
		}
		select {
		case <-ctx.Done():
			return before
		case <-tick.C:
		}
	}
}

// peerPathsFrom lists every peer in st, online first, then by OS.
func peerPathsFrom(st *ipnstate.Status) []PeerPath {
	paths := []PeerPath{}
	if st == nil {
		return paths
	}
	for _, k := range st.Peers() {
		paths = append(paths, peerPathFrom(st.Peer[k]))
	}
	slices.SortStableFunc(paths, func(a, b PeerPath) int {
		if a.Online != b.Online {
			if a.Online {
				return -1
			}
			return 1
		}
		return cmp.Compare(a.OS, b.OS)
	})
	return paths
}

// peerPathFrom classifies one peer's current path. CurAddr is set only while
// a direct path is in use; Relay is the relay region the peer homes on, which
// carries the traffic when there is no direct path.
func peerPathFrom(ps *ipnstate.PeerStatus) PeerPath {
	if ps == nil {
		return PeerPath{Path: PathIdle}
	}
	p := PeerPath{
		OS:            ps.OS,
		Online:        ps.Online,
		LastHandshake: ps.LastHandshake,
		RxBytes:       ps.RxBytes,
		TxBytes:       ps.TxBytes,
	}
	switch {
	case ps.CurAddr != "":
		p.Path, p.Network = PathDirect, addressNetwork(ps.CurAddr)
	case ps.PeerRelay != "":
		p.Path = PathPeerRelay
	case ps.Relay != "" && ps.Active:
		p.Path, p.RelayRegion = PathRelay, ps.Relay
	default:
		p.Path, p.RelayRegion = PathIdle, ps.Relay
	}
	return p
}

// addressNetwork says whether addr (ip:port) is on a private network or the
// public internet. Only the class leaves this function, never the address.
func addressNetwork(addr string) string {
	ap, err := netip.ParseAddrPort(addr)
	if err != nil {
		return ""
	}
	ip := ap.Addr().Unmap()
	cgnat := netip.MustParsePrefix("100.64.0.0/10")
	if ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || cgnat.Contains(ip) {
		return NetworkLAN
	}
	return NetworkInternet
}

// networkCheckFrom summarizes r without its addresses. st supplies the
// preferred relay's region code, which r holds only as a number.
func networkCheckFrom(r *netcheck.Report, st *ipnstate.Status) *NetworkCheck {
	if r == nil {
		return nil
	}
	nc := &NetworkCheck{
		At:                         r.Now,
		UDP:                        r.UDP,
		IPv4:                       r.IPv4,
		IPv6:                       r.IPv6,
		MappingVariesByDestination: optString(r.MappingVariesByDestIP),
		UPnP:                       optString(r.UPnP),
		NATPMP:                     optString(r.PMP),
		PCP:                        optString(r.PCP),
	}
	if st != nil && st.Self != nil {
		nc.PreferredRelay = st.Self.Relay
	}
	if d, ok := r.RegionLatency[r.PreferredDERP]; ok && r.PreferredDERP != 0 {
		nc.PreferredRelayLatencyMs = float64(d.Microseconds()) / 1000
	}
	return nc
}

// optString is "yes", "no" or "unknown".
func optString(b opt.Bool) string {
	v, ok := b.Get()
	switch {
	case !ok:
		return "unknown"
	case v:
		return "yes"
	default:
		return "no"
	}
}

// describePath is one peer's path for a log line: "direct (lan)",
// "relay (nyc)", "idle".
func describePath(p PeerPath) string {
	switch {
	case p.Path == PathDirect && p.Network != "":
		return fmt.Sprintf("%s (%s)", p.Path, p.Network)
	case p.Path == PathRelay && p.RelayRegion != "":
		return fmt.Sprintf("%s (%s)", p.Path, p.RelayRegion)
	default:
		return p.Path
	}
}

// describeNetwork is a network check for a log line.
func describeNetwork(nc *NetworkCheck) string {
	parts := []string{
		fmt.Sprintf("udp=%v", nc.UDP),
		fmt.Sprintf("ipv4=%v", nc.IPv4),
		fmt.Sprintf("ipv6=%v", nc.IPv6),
		"mapping-varies-by-destination=" + nc.MappingVariesByDestination,
		"upnp=" + nc.UPnP,
		"nat-pmp=" + nc.NATPMP,
		"pcp=" + nc.PCP,
	}
	if nc.PreferredRelay != "" {
		parts = append(parts, fmt.Sprintf("relay=%s (%.1f ms)", nc.PreferredRelay, nc.PreferredRelayLatencyMs))
	}
	return strings.Join(parts, " ")
}

// pathTracker remembers each peer's last path, so watchPaths logs a change
// once. Peers are known by their node key, which never leaves the tracker;
// a log line names a peer by its OS and the order it was first seen in.
type pathTracker struct {
	last    map[key.NodePublic]string
	label   map[key.NodePublic]string
	seen    int
	network string
}

func newPathTracker() *pathTracker {
	return &pathTracker{last: map[key.NodePublic]string{}, label: map[key.NodePublic]string{}}
}

// changes compares st with the last status it saw and returns one line per
// peer whose path changed, and one when the network check changed. A path
// going idle is not a change worth a line: an idle peer keeps the path it
// had until it next sends traffic.
func (t *pathTracker) changes(st *ipnstate.Status, nc *NetworkCheck) []string {
	var lines []string
	if nc != nil {
		if d := describeNetwork(nc); d != t.network {
			t.network = d
			lines = append(lines, "network check: "+d)
		}
	}
	if st == nil {
		return lines
	}
	for _, k := range st.Peers() {
		p := peerPathFrom(st.Peer[k])
		if p.Path == PathIdle {
			continue
		}
		now := describePath(p)
		label, ok := t.label[k]
		if !ok {
			t.seen++
			label = fmt.Sprintf("%s peer %d", cmp.Or(p.OS, "unknown"), t.seen)
			t.label[k] = label
		}
		before, had := t.last[k]
		if had && before == now {
			continue
		}
		t.last[k] = now
		if had {
			lines = append(lines, fmt.Sprintf("path to %s changed: %s -> %s", label, before, now))
		} else {
			lines = append(lines, fmt.Sprintf("path to %s: %s", label, now))
		}
	}
	return lines
}

// watchPaths logs each peer's path when it is first used and whenever it
// changes between direct and relayed, and the network check when it first
// lands and whenever it changes (#3883). It runs until s stops being the
// current node.
func watchPaths(s *tsnet.Server) {
	tracker := newPathTracker()
	tick := time.NewTicker(pathWatchInterval)
	defer tick.Stop()
	for range tick.C {
		if currentServer() != s {
			return
		}
		lc, err := s.LocalClient()
		if err != nil {
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		st, err := lc.Status(ctx)
		var nc *NetworkCheck
		if err == nil {
			nc = networkCheckFrom(lastNetcheck(ctx, s), st)
		}
		cancel()
		if err != nil {
			continue
		}
		for _, line := range tracker.changes(st, nc) {
			log.Printf("[remote] %s", line)
		}
	}
}
