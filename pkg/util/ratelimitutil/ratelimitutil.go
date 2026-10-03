// Package ratelimitutil provides a per-IP token-bucket rate limiter for
// protecting sensitive endpoints (e.g. login, setup, recover) from brute-force
// and credential-stuffing attacks, and LoginGuard, which locks out an address
// or account after repeated failed sign-ins (#1861).
package ratelimitutil

import (
	"net"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

const (
	// DefaultRate is the number of requests allowed per second per IP.
	DefaultRate rate.Limit = 5
	// DefaultBurst is the maximum burst size for a single IP.
	DefaultBurst = 10
	// cleanupInterval is how often expired entries are removed from the map.
	cleanupInterval = 5 * time.Minute
	// ttl is how long an idle IP entry is kept before being removed.
	ttl = 15 * time.Minute
)

// Limiter holds per-IP rate limiters.
type Limiter struct {
	mu      sync.Mutex
	entries map[string]*entry
	r       rate.Limit
	b       int
}

// New returns a Limiter with the default rate and burst.
func New() *Limiter {
	return NewWithRate(DefaultRate, DefaultBurst)
}

// NewWithRate returns a Limiter with custom rate (per second) and burst.
func NewWithRate(r rate.Limit, b int) *Limiter {
	l := &Limiter{
		entries: make(map[string]*entry),
		r:       r,
		b:       b,
	}
	go l.cleanup()
	return l
}

// Allow returns true if the request from ip is within the rate limit.
func (l *Limiter) Allow(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	e, ok := l.entries[ip]
	if !ok {
		e = &entry{limiter: rate.NewLimiter(l.r, l.b)}
		l.entries[ip] = e
	}
	e.lastSeen = time.Now()
	return e.limiter.Allow()
}

// AllowN returns true if n tokens are available for ip.
func (l *Limiter) AllowN(ip string, n int) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	e, ok := l.entries[ip]
	if !ok {
		e = &entry{limiter: rate.NewLimiter(l.r, l.b)}
		l.entries[ip] = e
	}
	e.lastSeen = time.Now()
	return e.limiter.AllowN(time.Now(), n)
}

// cleanup periodically removes entries that haven't been seen for ttl duration.
func (l *Limiter) cleanup() {
	ticker := time.NewTicker(cleanupInterval)
	defer ticker.Stop()
	for range ticker.C {
		l.mu.Lock()
		for ip, e := range l.entries {
			if time.Since(e.lastSeen) > ttl {
				delete(l.entries, ip)
			}
		}
		l.mu.Unlock()
	}
}

// ExtractIP returns the client IP from a raw address string, stripping the port.
// Falls back to the full address if parsing fails.
func ExtractIP(addr string) string {
	if host, _, err := net.SplitHostPort(addr); err == nil {
		return host
	}
	return addr
}

// LoginGuard defaults. A person mistyping a password a few times never meets
// a lockout; a guesser meets one after PairThreshold tries and waits twice as
// long after each further miss, up to MaxLockout.
const (
	// DefaultPairThreshold is the failures one address may make against one
	// account before it is locked out of that account.
	DefaultPairThreshold = 5
	// DefaultIPThreshold is the failures one address may make across every
	// account before it is locked out of all of them.
	DefaultIPThreshold = 20
	// DefaultAccountThreshold is the failures one account may take from every
	// address before addresses it has not signed in from are locked out of it.
	DefaultAccountThreshold = 50
	// DefaultBaseLockout is the first lockout's length.
	DefaultBaseLockout = 30 * time.Second
	// DefaultMaxLockout caps a lockout, so none is permanent.
	DefaultMaxLockout = 15 * time.Minute
	// DefaultFailureReset is how long after its last failure, with no lockout
	// running, a count is forgotten.
	DefaultFailureReset = time.Hour
	// maxGuardRecords bounds the failure table. An attacker picks the
	// usernames and, on IPv6, a lot of addresses; past the bound a new key is
	// not tracked, and the per-IP token bucket is still in front of it.
	maxGuardRecords = 50_000
)

// LoginGuard counts failed sign-ins per (account, address), per address and
// per account, and locks a key out with exponential backoff once its count
// crosses a threshold. Every lockout expires.
//
// Its state is in memory and dies with the process, by design: nothing is
// written to the database or to a drive, so a drive moved to another Quark
// carries no lockout with it and a restart clears a lockout that went wrong.
// Accounts are keyed by the username as typed, whether or not one exists, so
// a lockout says nothing about which usernames are real.
//
// A nil *LoginGuard checks nothing and records nothing.
type LoginGuard struct {
	mu        sync.Mutex
	now       func() time.Time
	policy    LoginGuardParams
	records   map[string]*guardRecord
	known     map[string]map[string]struct{}
	lastSweep time.Time
}

// LoginGuardParams configures a LoginGuard. A zero field takes its default.
type LoginGuardParams struct {
	// Now is the clock; nil means time.Now.
	Now              func() time.Time
	PairThreshold    int
	IPThreshold      int
	AccountThreshold int
	BaseLockout      time.Duration
	MaxLockout       time.Duration
	FailureReset     time.Duration
}

// LoginAttempt names who is signing in and from where.
type LoginAttempt struct {
	// Account is the username as the caller typed it.
	Account string
	// IP is the client address, without a port.
	IP string
}

// LoginCheckResult is Check's answer.
type LoginCheckResult struct {
	// RetryAfter is how long until the attempt may be made, zero when it may
	// be made now.
	RetryAfter time.Duration
}

// NewLoginGuard returns an empty LoginGuard.
func NewLoginGuard(params LoginGuardParams) *LoginGuard {
	now := params.Now
	if now == nil {
		now = time.Now
	}
	return &LoginGuard{
		now:     now,
		policy:  withDefaults(params),
		records: make(map[string]*guardRecord),
		known:   make(map[string]map[string]struct{}),
	}
}

// Check reports how long the attempt must wait: the longest lockout running
// on its pair, its address, or — unless the account has signed in from this
// address before — its account.
func (g *LoginGuard) Check(a LoginAttempt) LoginCheckResult {
	if g == nil {
		return LoginCheckResult{}
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	now := g.now()
	account, ip := accountKey(a.Account), addressKey(a.IP)
	var wait time.Duration
	for _, key := range g.keysFor(account, ip, true) {
		if r, ok := g.records[key]; ok {
			wait = max(wait, r.lockedUntil.Sub(now))
		}
	}
	return LoginCheckResult{RetryAfter: wait}
}

// RecordFailure counts a failed sign-in against the attempt's pair, address
// and account, starting or lengthening a lockout on any that cross their
// threshold.
func (g *LoginGuard) RecordFailure(a LoginAttempt) {
	if g == nil {
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	now := g.now()
	g.sweep(now)
	account, ip := accountKey(a.Account), addressKey(a.IP)
	thresholds := []int{g.policy.PairThreshold, g.policy.IPThreshold, g.policy.AccountThreshold}
	for i, key := range g.keysFor(account, ip, false) {
		r, ok := g.records[key]
		if !ok {
			if len(g.records) >= maxGuardRecords {
				continue
			}
			r = &guardRecord{}
			g.records[key] = r
		}
		if r.stale(now, g.policy.FailureReset) {
			*r = guardRecord{}
		}
		r.failures++
		r.lastFailure = now
		if over := r.failures - thresholds[i]; over >= 0 {
			r.lockedUntil = now.Add(backoff(g.policy.BaseLockout, g.policy.MaxLockout, over))
		}
	}
}

// RecordSuccess forgets the pair's failures and remembers the address as one
// the account signs in from, which exempts it from the account-wide lockout.
// The address's own count stands: one right guess among many wrong ones does
// not clear a sprayer.
func (g *LoginGuard) RecordSuccess(a LoginAttempt) {
	if g == nil {
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	account, ip := accountKey(a.Account), addressKey(a.IP)
	delete(g.records, pairKey(account, ip))
	if g.known[account] == nil {
		g.known[account] = make(map[string]struct{})
	}
	g.known[account][ip] = struct{}{}
}

// keysFor lists the attempt's pair, address and account keys, in that order.
// When checking, the account key is left out for an address the account has
// signed in from.
func (g *LoginGuard) keysFor(account, ip string, checking bool) []string {
	keys := []string{pairKey(account, ip), "ip\x00" + ip}
	if _, known := g.known[account][ip]; checking && known {
		return keys
	}
	return append(keys, "account\x00"+account)
}

// sweep drops forgotten records, at most once a minute.
func (g *LoginGuard) sweep(now time.Time) {
	if now.Sub(g.lastSweep) < time.Minute {
		return
	}
	g.lastSweep = now
	for key, r := range g.records {
		if r.stale(now, g.policy.FailureReset) {
			delete(g.records, key)
		}
	}
}
