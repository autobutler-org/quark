// Package remoteutil runs an embedded Tailscale node and reverse-proxies
// tailnet traffic to the local quark server.
package remoteutil

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
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

// Disable turns remote access off for good: it logs the node out of the
// tailnet, stops it, and deletes its state dir, so HasPersistedState is false
// afterwards and the next enable needs a fresh key. Stop is the shutdown path
// and keeps the enrollment; this is the user saying "off".
func Disable() error {
	mu.Lock()
	s := srv
	mu.Unlock()
	if s != nil {
		if lc, err := s.LocalClient(); err == nil {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			// Best effort: an unreachable control server must not keep the node
			// on. Deleting the state below disowns it locally either way.
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
	if err := os.RemoveAll(stateDir()); err != nil {
		return fmt.Errorf("failed to remove tsnet state dir: %w", err)
	}
	return nil
}

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
// request. It is idempotent: if the proxy listener is already open, it
// returns nil immediately.
//
// The proxy is intentionally unauthenticated at the tsnet layer — access
// control is enforced by the proxied quark server's own auth middleware. Only
// peers on the tailnet can reach this listener.
func StartProxy(localPort int, localTLS bool) error {
	mu.Lock()
	defer mu.Unlock()
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
		if err := http.Serve(ln, rp); err != nil {
			log.Printf("[tsnet] proxy stopped: %v", err)
		}
	}()
	return nil
}

// EnsureStarted starts the tsnet node and its proxy. provisionFn is called
// only when there is no persisted tsnet state: the state is the node's
// credential, so a restart reuses it and only a first enable, or one after
// Disable, needs a fresh Headscale pre-auth key. The proxy is started against
// localPort after tsnet starts successfully; localTLS must match how the
// server is serving that port. Every failure is recorded for Status.
func EnsureStarted(localPort int, localTLS bool, provisionFn func() (string, error)) error {
	if IsRunning() {
		return nil
	}

	authKey := ""
	if !HasPersistedState() {
		log.Printf("[remote] no persisted tsnet state, provisioning a key")
		key, err := provisionFn()
		if err != nil {
			err = fmt.Errorf("provision: %w", err)
			mu.Lock()
			lastErr = err
			mu.Unlock()
			return err
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
