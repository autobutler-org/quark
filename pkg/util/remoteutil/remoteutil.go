// Package remoteutil runs an embedded Tailscale node and reverse-proxies
// tailnet traffic to the local quark server.
package remoteutil

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/provisionutil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"golang.org/x/time/rate"
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
	// ErrTooManyPairs means the account has asked for more keys than
	// PairDeviceBurst allows (#3785).
	ErrTooManyPairs = errors.New("this account has set up too many devices recently; wait a while and try again")
)

// Each account's budget for PairDevice (#3785). The provisioning service
// limits a household to 30 keys an hour (#2317), so without this one account
// could spend the whole household's budget and leave everyone else unable to
// pair. A phone asks once, and again only after its key is rejected, so three
// at once covers a phone, a tablet and a retry. The limiter forgets an
// account that has been idle for 15 minutes, so the most one account can take
// is PairDeviceBurst every 15 minutes, 12 an hour.
const (
	// PairDeviceRate is the sustained keys per second: one every 30 minutes.
	PairDeviceRate = rate.Limit(1.0 / (30 * 60))
	// PairDeviceBurst is how many keys an account may ask for at once.
	PairDeviceBurst = 3
)

// AccessState is what Settings should treat remote access as. It is derived
// from the stored flag and whether setup enrolled this Quark, so a flag left
// over from before setup is not on (#3611).
type AccessState struct {
	// On is the switch: an admin turned remote access on and enrollment
	// finished. A stored flag alone is not on.
	On bool
	// NeedsSetup is a stored flag whose enrollment never finished. The client
	// offers the setup sheet. Nothing in this state turns remote access on.
	NeedsSetup bool
}

// DeriveAccessState maps the stored flag and enrollment to AccessState. It
// reads nothing, so every combination can be pinned without a Quark.
func DeriveAccessState(enabled, enrolled bool) AccessState {
	if !enabled {
		return AccessState{}
	}
	if !enrolled {
		return AccessState{NeedsSetup: true}
	}
	return AccessState{On: true}
}

// Enrolled reports whether setup stored a household credential. That
// credential is what enrollment writes, and what a Quark enabled before
// households, or with a key an admin supplied, does not have.
func Enrolled() bool {
	household, token := settingsutil.GetHousehold()
	return household != "" && token != ""
}

// PairDeviceParams is who is asking for a key, and the limiter they spend
// it from.
type PairDeviceParams struct {
	// Account is the signed-in account asking. It is the limiter's key.
	Account string
	// Limiter is the per-account budget, normally built with PairDeviceRate
	// and PairDeviceBurst.
	Limiter *ratelimitutil.Limiter
}

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
// call when a key could not be used, and with ErrTooManyPairs when the account
// has spent its budget. Only a request that reaches the provisioning service
// spends from the budget.
func PairDevice(params PairDeviceParams) (PairDeviceResult, error) {
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
	if params.Limiter == nil || !params.Limiter.Allow(params.Account) {
		return PairDeviceResult{}, ErrTooManyPairs
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
	// A stored flag from before setup is not consent to connect. Enrollment
	// is what an admin's setup writes; without it, do not provision a key
	// and do not start the node (#3611).
	if !Enrolled() {
		log.Printf("[remote] remote access is not set up; not starting the node")
		return nil
	}
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
