package ratelimitutil

import (
	"net"
	"slices"
	"strings"
	"time"
)

// withDefaults fills each zero field of params with its default.
func withDefaults(params LoginGuardParams) LoginGuardParams {
	params.PairThreshold = orDefault(params.PairThreshold, DefaultPairThreshold)
	params.IPThreshold = orDefault(params.IPThreshold, DefaultIPThreshold)
	params.AccountThreshold = orDefault(params.AccountThreshold, DefaultAccountThreshold)
	params.BaseLockout = orDefault(params.BaseLockout, DefaultBaseLockout)
	params.MaxLockout = orDefault(params.MaxLockout, DefaultMaxLockout)
	params.FailureReset = orDefault(params.FailureReset, DefaultFailureReset)
	return params
}

// orDefault returns v, or def when v is the zero value.
func orDefault[T comparable](v, def T) T {
	var zero T
	if v == zero {
		return def
	}
	return v
}

// backoff is base doubled over times, capped at limit.
func backoff(base, limit time.Duration, over int) time.Duration {
	d := base
	for range over {
		if d >= limit/2 {
			return limit
		}
		d *= 2
	}
	return min(d, limit)
}

// accountKey folds case, so "Admin" and "admin" share one count.
func accountKey(account string) string {
	return strings.ToLower(account)
}

// addressKey is the address itself for IPv4 and its /64 for IPv6, the
// smallest block a single subscriber is usually handed.
func addressKey(ip string) string {
	parsed := net.ParseIP(ip)
	if parsed == nil || parsed.To4() != nil {
		return ip
	}
	return parsed.Mask(net.CIDRMask(64, 128)).String() + "/64"
}

// pairKey keys one account at one address.
func pairKey(account, ip string) string {
	return "pair\x00" + account + "\x00" + ip
}

// evict makes room in a full failure table by dropping a tenth of it, so the
// O(n log n) pass runs once per several thousand new keys rather than on each.
// Forgotten records go first, then the counts idle longest with no lockout
// running, and only then the lockouts closest to ending: a spray that fills
// the table pushes out other idle counts, not the lockout it is under.
func (g *LoginGuard) evict(now time.Time) {
	type candidate struct {
		key    string
		locked bool
		// at orders candidates of one kind: the last failure of an idle count,
		// the lockout's end for a running one.
		at time.Time
	}
	candidates := make([]candidate, 0, len(g.records))
	for key, r := range g.records {
		if r.stale(now, g.policy.FailureReset) {
			delete(g.records, key)
			continue
		}
		c := candidate{key: key, locked: now.Before(r.lockedUntil), at: r.lastFailure}
		if c.locked {
			c.at = r.lockedUntil
		}
		candidates = append(candidates, c)
	}
	excess := len(g.records) - (maxGuardRecords - maxGuardRecords/10)
	if excess <= 0 {
		return
	}
	slices.SortFunc(candidates, func(a, b candidate) int {
		if a.locked != b.locked {
			if a.locked {
				return 1
			}
			return -1
		}
		return a.at.Compare(b.at)
	})
	for _, c := range candidates[:excess] {
		delete(g.records, c.key)
	}
}
