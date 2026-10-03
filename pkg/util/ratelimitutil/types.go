package ratelimitutil

import (
	"time"

	"golang.org/x/time/rate"
)

type entry struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

// guardRecord is one LoginGuard key's failure count and lockout.
type guardRecord struct {
	failures    int
	lastFailure time.Time
	lockedUntil time.Time
}

// stale reports whether the record has nothing running and its last failure
// is older than reset, so its count no longer matters.
func (r *guardRecord) stale(now time.Time, reset time.Duration) bool {
	return !now.Before(r.lockedUntil) && now.Sub(r.lastFailure) > reset
}
