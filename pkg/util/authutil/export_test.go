package authutil

import "time"

// Test hooks for the external authutil_test package.
const (
	SessionDuration      = sessionDuration
	SessionMaxLifetime   = sessionMaxLifetime
	SessionRenewInterval = sessionRenewInterval
)

// Wordlist is the recovery phrase wordlist.
var Wordlist = wordlist

// SetNow pins the session clock to t and returns a function restoring it, so
// expiry tests can wind time forward instead of sleeping. Not safe for
// parallel tests — the clock is package state.
func SetNow(t time.Time) func() {
	prev := now
	now = func() time.Time { return t }
	return func() { now = prev }
}
