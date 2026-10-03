package ratelimitutil

import (
	"net"
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
