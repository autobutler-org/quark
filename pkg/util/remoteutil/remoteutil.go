// Package remoteutil runs an embedded Tailscale node and reverse-proxies
// tailnet traffic to the local quark server.
package remoteutil

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/provisionutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"tailscale.com/tsnet"
)

const defaultControlURL = "https://quark.ts.autobutler.org"

// errKeyRejected is Status's error for a node stuck in NeedsLogin.
const errKeyRejected = "the tailnet rejected the auth key, or it expired"

var (
	mu      sync.Mutex
	srv     *tsnet.Server
	proxyLn net.Listener
	running bool
	// lastErr is the most recent start or proxy failure, so a boot that only
	// logged it can still be shown in Settings (#1815). Cleared by a successful
	// Start and by Disable.
	//
	// ponytail: package state like the rest of this file; it belongs on
	// deputil.Dependencies (#1674) once remote access is reworked there.
	lastErr error
	// stops counts stops of the node, so superviseLogin can tell whether a
	// Disable or Stop landed while it was provisioning a fresh key.
	stops uint64
	// testStatus, when set, is what Status reports; see SetStatusForTesting.
	testStatus *StatusResult
)

// PairDevice's refusals. Each says what to do next.
var (
	// ErrCustomTailnet means the Quark joins a tailnet the user runs (#1810),
	// where Quark cannot mint keys.
	ErrCustomTailnet = errors.New("this Quark is on your own tailnet; add the device there instead")
	// ErrRemoteAccessOff means an admin has not turned remote access on.
	ErrRemoteAccessOff = errors.New("remote access is off; ask an admin to turn it on in Settings")
	// ErrNoHousehold means the Quark enrolled before households (#2358), or
	// with a key an admin supplied, so it has no credential to pair with.
	ErrNoHousehold = errors.New("this Quark has no household to add devices to; an admin can turn remote access off and on again to re-enroll it")
	// ErrNotConnected means remote access is on but the node has not joined
	// the tailnet yet.
	ErrNotConnected = errors.New("remote access is still connecting; try again in a moment")
)

// PairDeviceResult is what a device needs to join the Quark's household and
// reach it.
type PairDeviceResult struct {
	// AuthKey is a single-use pre-auth key in the Quark's household.
	AuthKey string
	// ControlURL is the Headscale server the device registers with.
	ControlURL string
	// QuarkAddress is the Quark's URL on the tailnet.
	QuarkAddress string
}

// PairDevice asks the provisioning service for a key that adds one more
// device, such as a phone, to this Quark's household (#2359). It presents the
// household credential from settings (pair mode, #2358) with a fresh random
// device ID, since each device is its own node. It fails with ErrCustomTailnet,
// ErrRemoteAccessOff, ErrNoHousehold or ErrNotConnected before any network
// call when a key could not be used.
func PairDevice() (PairDeviceResult, error) {
	control := controlURL()
	if control != defaultControlURL {
		return PairDeviceResult{}, ErrCustomTailnet
	}
	if !settingsutil.GetRemoteAccess() {
		return PairDeviceResult{}, ErrRemoteAccessOff
	}
	household, token := settingsutil.GetHousehold()
	if household == "" || token == "" {
		return PairDeviceResult{}, ErrNoHousehold
	}
	status := Status()
	if !status.Connected || status.RemoteURL == "" {
		return PairDeviceResult{}, ErrNotConnected
	}
	deviceID, err := newPairDeviceID()
	if err != nil {
		return PairDeviceResult{}, err
	}
	key, err := provisionutil.ProvisionAuthKey(provisionutil.ProvisionAuthKeyParams{
		DeviceID:       deviceID,
		Household:      household,
		HouseholdToken: token,
	})
	if err != nil {
		return PairDeviceResult{}, fmt.Errorf("provision a device key: %w", err)
	}
	return PairDeviceResult{
		AuthKey:      key.AuthKey,
		ControlURL:   control,
		QuarkAddress: status.RemoteURL,
	}, nil
}

// SetStatusForTesting makes Status report s until the returned function is
// called, so a handler test can stand in a connected node without a tailnet.
func SetStatusForTesting(s StatusResult) (restore func()) {
	mu.Lock()
	defer mu.Unlock()
	testStatus = &s
	return func() {
		mu.Lock()
		defer mu.Unlock()
		testStatus = nil
	}
}

// StatusResult is what the tsnet node is doing right now.
type StatusResult struct {
	// Connected is true only once the node has authenticated and tsnet reports
	// BackendState "Running" — not merely because Start returned.
	Connected bool
	// RemoteURL is the node's tailnet URL, set only when Connected.
	RemoteURL string
	// Error is the last start or proxy failure, or "" if there was none.
	Error string
}

func Start(authKey string) error {
	mu.Lock()
	defer mu.Unlock()
	return startLocked(authKey)
}

func Stop() {
	mu.Lock()
	defer mu.Unlock()
	stopLocked()
}

func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return running
}

// Status reports whether the node reached the tailnet, and the last start
// failure. The mutex is held only long enough to snapshot state; the call to
// the local Tailscale backend happens outside the lock so that Stop() and
// IsRunning() are never blocked by I/O.
func Status() StatusResult {
	mu.Lock()
	if testStatus != nil {
		defer mu.Unlock()
		return *testStatus
	}
	s := srv
	result := StatusResult{}
	if lastErr != nil {
		result.Error = lastErr.Error()
	}
	mu.Unlock()
	if s == nil {
		return result
	}

	lc, err := s.LocalClient()
	if err != nil {
		return result
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	st, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		return result
	}
	conn := connectionFromStatus(st)
	result.Connected, result.RemoteURL = conn.Connected, conn.RemoteURL
	if result.Error == "" {
		result.Error = conn.Error
	}
	return result
}

// Disable turns remote access off: it logs the node out of the tailnet and
// stops it. The state dir stays, because it holds the machine key: Enable
// presents that key again with a fresh pre-auth key, and Headscale
// re-registers the same node with the same tailnet IPs (#2469). Stop is the
// shutdown path and keeps the node logged in; this is the user saying "off".
func Disable() error {
	mu.Lock()
	s := srv
	mu.Unlock()
	if s != nil {
		if lc, err := s.LocalClient(); err == nil {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			// Best effort: an unreachable control server must not keep the node
			// on. The node is stopped below either way.
			if err := lc.Logout(ctx); err != nil {
				log.Printf("[remote] logout failed: %v", err)
			}
			cancel()
		}
	}
	Stop()
	mu.Lock()
	lastErr = nil
	mu.Unlock()
	return nil
}

// HasPersistedState returns true if tsnet has written state to disk. That
// state holds the machine key and, unless Disable logged the node out, the
// node key that lets it reconnect without a new auth key. EnsureStarted reads
// it as "no key needed"; Enable does not, since Disable leaves it behind.
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
// request. It is idempotent: if the proxy listener is already open, it
// returns nil immediately.
//
// The proxy is intentionally unauthenticated at the tsnet layer — access
// control is enforced by the proxied quark server's own auth middleware. Only
// peers on the tailnet can reach this listener.
func StartProxy(localPort int, localTLS bool) error {
	mu.Lock()
	defer mu.Unlock()
	return startProxyLocked(localPort, localTLS)
}

// EnsureStarted is the boot path: it starts the tsnet node and its proxy,
// reusing persisted tsnet state. provisionFn is called only when there is no
// state, since a node that was on when the Quark stopped is still logged in.
// The proxy is started against localPort after tsnet starts successfully;
// localTLS must match how the server is serving that port. Every failure is
// recorded for Status.
//
// It returns once the node has started, before it has logged in, and watches
// the login in the background. If control rejects the persisted state and
// asks for an interactive login, the node re-enrolls once with a fresh key; if
// it still needs a login, it is stopped and Status reports why (#2466).
func EnsureStarted(localPort int, localTLS bool, provisionFn func() (string, error)) error {
	return ensureStarted(false, localPort, localTLS, provisionFn)
}

// Enable is the user turning remote access on. It is EnsureStarted, except
// that it always presents a fresh key from provisionFn: it follows a Disable,
// which logged the node out but kept its machine key, or a failure. With the
// same machine key and a fresh pre-auth key, Headscale re-registers the
// existing node and keeps its tailnet IPs (#2469). A node still logged in
// ignores the key and reconnects from its state.
func Enable(localPort int, localTLS bool, provisionFn func() (string, error)) error {
	return ensureStarted(true, localPort, localTLS, provisionFn)
}

// GetCertificate implements the tls.Config.GetCertificate callback. When
// Tailscale is running it returns a Tailscale-managed Let's Encrypt certificate
// for the node's *.ts.net hostname, falling back to the provided fallback
// function (typically the self-signed cert) when not running or when the
// ServerName in the ClientHelloInfo does not match the Tailscale hostname.
//
// Wire this into the server's tls.Config:
//
//	tlsCfg.GetCertificate = remoteutil.GetCertificate(selfSignedFallback)
func GetCertificate(fallback func(*tls.ClientHelloInfo) (*tls.Certificate, error)) func(*tls.ClientHelloInfo) (*tls.Certificate, error) {
	return func(hi *tls.ClientHelloInfo) (*tls.Certificate, error) {
		mu.Lock()
		s := srv
		mu.Unlock()
		if s != nil {
			lc, err := s.LocalClient()
			if err == nil {
				cert, err := lc.GetCertificate(hi)
				if err == nil {
					return cert, nil
				}
				// GetCertificate fails when the ServerName doesn't match the
				// Tailscale hostname (e.g. a LAN client hitting the IP directly).
				// Fall through to the self-signed cert.
			}
		}
		if fallback != nil {
			return fallback(hi)
		}
		return nil, fmt.Errorf("no certificate available")
	}
}

// TailscaleHostname returns the node's fully-qualified *.ts.net hostname when
// Tailscale is running, or "" if not connected.
func TailscaleHostname() string {
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
	if err != nil || st.Self == nil {
		return ""
	}
	return strings.TrimSuffix(st.Self.DNSName, ".")
}
