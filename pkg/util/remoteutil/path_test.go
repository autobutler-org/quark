// cspell:words netcheck natpmp upnp

package remoteutil

import (
	"strings"
	"testing"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/netcheck"
	"tailscale.com/types/key"
	"tailscale.com/types/opt"
)

// TestPeerPathFrom pins how a peer's status maps to a path (#3883): a
// current address is direct, labeled by whether it is private or public; an
// active peer with none is relayed through its home region; a quiet one is
// idle.
func TestPeerPathFrom(t *testing.T) {
	cases := []struct {
		name string
		ps   ipnstate.PeerStatus
		want PeerPath
	}{
		{"direct on the home network", ipnstate.PeerStatus{OS: "iOS", CurAddr: "192.168.1.20:41641", Relay: "nyc", Active: true},
			PeerPath{OS: "iOS", Path: PathDirect, Network: NetworkLAN}},
		{"direct over the internet", ipnstate.PeerStatus{OS: "iOS", CurAddr: "203.0.113.9:3478", Relay: "nyc", Active: true},
			PeerPath{OS: "iOS", Path: PathDirect, Network: NetworkInternet}},
		{"direct over IPv6", ipnstate.PeerStatus{OS: "android", CurAddr: "[2001:db8::1]:41641", Active: true},
			PeerPath{OS: "android", Path: PathDirect, Network: NetworkInternet}},
		{"relayed", ipnstate.PeerStatus{OS: "iOS", Relay: "sea", Active: true},
			PeerPath{OS: "iOS", Path: PathRelay, RelayRegion: "sea"}},
		{"through a peer relay", ipnstate.PeerStatus{OS: "iOS", PeerRelay: "10.0.0.2:7777:vni:1", Relay: "sea", Active: true},
			PeerPath{OS: "iOS", Path: PathPeerRelay}},
		{"idle", ipnstate.PeerStatus{OS: "iOS", Relay: "sea"},
			PeerPath{OS: "iOS", Path: PathIdle, RelayRegion: "sea"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := peerPathFrom(&tc.ps); got != tc.want {
				t.Errorf("peerPathFrom = %+v; want %+v", got, tc.want)
			}
		})
	}
}

// TestPeerPathFrom_CarriesCounters keeps the handshake and byte counts, the
// numbers a measurement run reads.
func TestPeerPathFrom_CarriesCounters(t *testing.T) {
	hs := time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC)
	got := peerPathFrom(&ipnstate.PeerStatus{Online: true, LastHandshake: hs, RxBytes: 10, TxBytes: 20})
	if !got.Online || !got.LastHandshake.Equal(hs) || got.RxBytes != 10 || got.TxBytes != 20 {
		t.Errorf("peerPathFrom = %+v; want online, the handshake and both byte counts", got)
	}
}

// TestAddressNetwork sorts addresses into private and public without
// returning them.
func TestAddressNetwork(t *testing.T) {
	for addr, want := range map[string]string{
		"10.1.2.3:1":            NetworkLAN,
		"172.16.0.1:1":          NetworkLAN,
		"192.168.0.1:1":         NetworkLAN,
		"100.100.1.1:1":         NetworkLAN,
		"169.254.1.1:1":         NetworkLAN,
		"[fd00::1]:1":           NetworkLAN,
		"[::ffff:10.0.0.1]:1":   NetworkLAN,
		"8.8.8.8:1":             NetworkInternet,
		"[2606:4700::1111]:443": NetworkInternet,
		"not an address":        "",
	} {
		if got := addressNetwork(addr); got != want {
			t.Errorf("addressNetwork(%q) = %q; want %q", addr, got, want)
		}
	}
}

// TestNetworkCheckFrom_HoldsNoAddresses maps a network check into the report
// without the public address it found (#3613's redaction rule).
func TestNetworkCheckFrom_HoldsNoAddresses(t *testing.T) {
	r := &netcheck.Report{
		Now:                   time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC),
		UDP:                   true,
		IPv4:                  true,
		MappingVariesByDestIP: opt.NewBool(true),
		UPnP:                  opt.NewBool(false),
		PreferredDERP:         2,
		RegionLatency:         netcheck.RegionLatency{2: 23500 * time.Microsecond},
	}
	st := &ipnstate.Status{Self: &ipnstate.PeerStatus{Relay: "sfo"}}
	nc := networkCheckFrom(r, st)
	want := NetworkCheck{
		At: r.Now, UDP: true, IPv4: true,
		MappingVariesByDestination: "yes", UPnP: "no", NATPMP: "unknown", PCP: "unknown",
		PreferredRelay: "sfo", PreferredRelayLatencyMs: 23.5,
	}
	if nc == nil || *nc != want {
		t.Fatalf("networkCheckFrom = %+v; want %+v", nc, want)
	}
	if networkCheckFrom(nil, st) != nil {
		t.Error("networkCheckFrom(nil) is not nil; want no check before the first one runs")
	}
}

// TestPathTracker_LogsChangesOnly logs a peer's path the first time it
// carries traffic and again only when it moves between relay and direct, and
// never puts an address or key in the line.
func TestPathTracker_LogsChangesOnly(t *testing.T) {
	phone := key.NewNode().Public()
	st := func(ps ipnstate.PeerStatus) *ipnstate.Status {
		return &ipnstate.Status{Peer: map[key.NodePublic]*ipnstate.PeerStatus{phone: &ps}}
	}
	tr := newPathTracker()

	steps := []struct {
		ps   ipnstate.PeerStatus
		want []string
	}{
		{ipnstate.PeerStatus{OS: "iOS", Relay: "nyc"}, nil},
		{ipnstate.PeerStatus{OS: "iOS", Relay: "nyc", Active: true}, []string{"path to iOS peer 1: relay (nyc)"}},
		{ipnstate.PeerStatus{OS: "iOS", Relay: "nyc", Active: true}, nil},
		{ipnstate.PeerStatus{OS: "iOS", CurAddr: "198.51.100.7:41641", Active: true},
			[]string{"path to iOS peer 1 changed: relay (nyc) -> direct (internet)"}},
		{ipnstate.PeerStatus{OS: "iOS", Relay: "nyc"}, nil},
		{ipnstate.PeerStatus{OS: "iOS", Relay: "nyc", Active: true},
			[]string{"path to iOS peer 1 changed: direct (internet) -> relay (nyc)"}},
	}
	for i, step := range steps {
		got := tr.changes(st(step.ps), nil)
		if strings.Join(got, "|") != strings.Join(step.want, "|") {
			t.Errorf("step %d: changes = %q; want %q", i, got, step.want)
		}
		for _, line := range got {
			if strings.Contains(line, "198.51.100.7") || strings.Contains(line, phone.String()) {
				t.Errorf("step %d: %q holds an address or key", i, line)
			}
		}
	}
}

// TestPathTracker_LogsNetworkCheckOnChange logs the network check when it
// first lands and when a field changes, not on every read.
func TestPathTracker_LogsNetworkCheckOnChange(t *testing.T) {
	tr := newPathTracker()
	nc := &NetworkCheck{UDP: true, MappingVariesByDestination: "no", UPnP: "no", NATPMP: "no", PCP: "no", PreferredRelay: "nyc", PreferredRelayLatencyMs: 12}
	if got := tr.changes(nil, nc); len(got) != 1 || !strings.HasPrefix(got[0], "network check: udp=true") {
		t.Fatalf("first check = %q; want one network check line", got)
	}
	again := *nc
	if got := tr.changes(nil, &again); len(got) != 0 {
		t.Errorf("unchanged check = %q; want nothing", got)
	}
	again.UPnP = "yes"
	if got := tr.changes(nil, &again); len(got) != 1 || !strings.Contains(got[0], "upnp=yes") {
		t.Errorf("changed check = %q; want a line with upnp=yes", got)
	}
}

// TestPathReport_Stopped reports a stopped node as not connected with no
// peers, so the endpoint answers before remote access is on.
func TestPathReport_Stopped(t *testing.T) {
	got, err := PathReport()
	if err != nil || got.Connected || got.Peers == nil || len(got.Peers) != 0 || got.Network != nil {
		t.Errorf("PathReport() = %+v, %v; want not connected, an empty peer list, no error", got, err)
	}
}
