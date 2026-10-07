package ratelimitutil_test

import (
	"fmt"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
)

// fakeClock is a clock a test moves by hand.
type fakeClock struct{ now time.Time }

func (c *fakeClock) Now() time.Time          { return c.now }
func (c *fakeClock) Advance(d time.Duration) { c.now = c.now.Add(d) }

func newGuard(clock *fakeClock) *ratelimitutil.LoginGuard {
	return ratelimitutil.NewLoginGuard(ratelimitutil.LoginGuardParams{
		Now:              clock.Now,
		PairThreshold:    3,
		IPThreshold:      6,
		AccountThreshold: 10,
		BaseLockout:      time.Minute,
		MaxLockout:       8 * time.Minute,
		FailureReset:     time.Hour,
	})
}

func fail(g *ratelimitutil.LoginGuard, a ratelimitutil.LoginAttempt, n int) {
	for range n {
		g.RecordFailure(a)
	}
}

// TestLoginGuard_LocksPairAfterThreshold: the failure that reaches the
// threshold starts a lockout, and failures under it do not.
func TestLoginGuard_LocksPairAfterThreshold(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}

	fail(g, a, 2)
	if got := g.Check(a).RetryAfter; got != 0 {
		t.Fatalf("locked after 2 failures, retry after %v", got)
	}
	fail(g, a, 1)
	if got := g.Check(a).RetryAfter; got != time.Minute {
		t.Fatalf("retry after = %v, want 1m", got)
	}
}

// TestLoginGuard_LockoutExpires: a lockout is temporary.
func TestLoginGuard_LockoutExpires(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}

	fail(g, a, 3)
	clock.Advance(30 * time.Second)
	if got := g.Check(a).RetryAfter; got != 30*time.Second {
		t.Fatalf("retry after = %v, want 30s", got)
	}
	clock.Advance(30 * time.Second)
	if got := g.Check(a).RetryAfter; got != 0 {
		t.Fatalf("still locked after the lockout ran out: %v", got)
	}
}

// TestLoginGuard_BackoffDoublesAndCaps: each failure past the threshold
// doubles the lockout, up to MaxLockout.
func TestLoginGuard_BackoffDoublesAndCaps(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}

	fail(g, a, 3)
	for _, want := range []time.Duration{2 * time.Minute, 4 * time.Minute, 8 * time.Minute, 8 * time.Minute} {
		clock.Advance(g.Check(a).RetryAfter)
		fail(g, a, 1)
		if got := g.Check(a).RetryAfter; got != want {
			t.Fatalf("retry after = %v, want %v", got, want)
		}
	}
}

// TestLoginGuard_SuccessClearsPair: signing in forgets the pair's failures.
func TestLoginGuard_SuccessClearsPair(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}

	fail(g, a, 2)
	g.RecordSuccess(a)
	fail(g, a, 2)
	if got := g.Check(a).RetryAfter; got != 0 {
		t.Fatalf("success did not clear the count: %v", got)
	}
}

// TestLoginGuard_FailuresDecay: failures older than FailureReset no longer
// count toward a lockout.
func TestLoginGuard_FailuresDecay(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}

	fail(g, a, 2)
	clock.Advance(time.Hour + time.Second)
	fail(g, a, 2)
	if got := g.Check(a).RetryAfter; got != 0 {
		t.Fatalf("stale failures still counted: %v", got)
	}
}

// TestLoginGuard_PairLockoutSparesOtherIPs: one address guessing at an
// account does not lock the owner out from theirs.
func TestLoginGuard_PairLockoutSparesOtherIPs(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)

	fail(g, ratelimitutil.LoginAttempt{Account: "admin", IP: "6.6.6.6"}, 3)
	if got := g.Check(ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}).RetryAfter; got != 0 {
		t.Fatalf("owner's address locked by another address's failures: %v", got)
	}
}

// TestLoginGuard_IPLockoutSpansAccounts: one address spraying many usernames
// is locked out once its total crosses IPThreshold, whichever account it
// tries next — including one that does not exist.
func TestLoginGuard_IPLockoutSpansAccounts(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)

	for i := range 6 {
		g.RecordFailure(ratelimitutil.LoginAttempt{Account: fmt.Sprintf("user%d", i), IP: "6.6.6.6"})
	}
	if got := g.Check(ratelimitutil.LoginAttempt{Account: "nobody", IP: "6.6.6.6"}).RetryAfter; got != time.Minute {
		t.Fatalf("retry after = %v, want 1m", got)
	}
	if got := g.Check(ratelimitutil.LoginAttempt{Account: "nobody", IP: "1.2.3.4"}).RetryAfter; got != 0 {
		t.Fatalf("another address locked: %v", got)
	}
}

// TestLoginGuard_IPv6KeyedByPrefix: an attacker cannot dodge the address
// lockout by walking the addresses of their own /64.
func TestLoginGuard_IPv6KeyedByPrefix(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)

	for i := range 6 {
		g.RecordFailure(ratelimitutil.LoginAttempt{Account: fmt.Sprintf("user%d", i), IP: fmt.Sprintf("2001:db8::%x", i+1)})
	}
	if got := g.Check(ratelimitutil.LoginAttempt{Account: "admin", IP: "2001:db8::ffff"}).RetryAfter; got == 0 {
		t.Fatal("a fresh address in the same /64 was not locked")
	}
	if got := g.Check(ratelimitutil.LoginAttempt{Account: "admin", IP: "2001:db8:0:1::1"}).RetryAfter; got != 0 {
		t.Fatalf("another /64 was locked: %v", got)
	}
}

// TestLoginGuard_AccountLockoutSparesKnownAddresses: a distributed attack
// on one account locks that account from new addresses, but an address the
// owner has signed in from still gets through, so the attacker cannot keep
// the owner out.
func TestLoginGuard_AccountLockoutSparesKnownAddresses(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	owner := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}
	g.RecordSuccess(owner)

	for i := range 10 {
		g.RecordFailure(ratelimitutil.LoginAttempt{Account: "admin", IP: fmt.Sprintf("10.0.0.%d", i)})
	}
	if got := g.Check(ratelimitutil.LoginAttempt{Account: "admin", IP: "10.0.1.1"}).RetryAfter; got != time.Minute {
		t.Fatalf("new address retry after = %v, want 1m", got)
	}
	if got := g.Check(owner).RetryAfter; got != 0 {
		t.Fatalf("owner's known address locked out: %v", got)
	}
}

// TestLoginGuard_AccountKeyIgnoresCase: "Admin" and "admin" share a count.
func TestLoginGuard_AccountKeyIgnoresCase(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)

	g.RecordFailure(ratelimitutil.LoginAttempt{Account: "Admin", IP: "1.2.3.4"})
	g.RecordFailure(ratelimitutil.LoginAttempt{Account: "ADMIN", IP: "1.2.3.4"})
	g.RecordFailure(ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"})
	if got := g.Check(ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}).RetryAfter; got == 0 {
		t.Fatal("case variants counted separately")
	}
}

// TestLoginGuard_NilIsOpen: a nil guard checks nothing and records nothing,
// so callers without one need no branch.
func TestLoginGuard_NilIsOpen(t *testing.T) {
	var g *ratelimitutil.LoginGuard
	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}
	g.RecordFailure(a)
	g.RecordSuccess(a)
	if got := g.Check(a).RetryAfter; got != 0 {
		t.Fatalf("nil guard locked: %v", got)
	}
}

// fillGuard sprays one failure each from fresh accounts and addresses until
// the failure table is full, the way a high-cardinality spray fills it. Each
// attempt adds three keys, and from numbers the first so sprays do not overlap.
func fillGuard(g *ratelimitutil.LoginGuard, from int) {
	for i := from; i <= from+ratelimitutil.MaxGuardRecords/3; i++ {
		g.RecordFailure(ratelimitutil.LoginAttempt{
			Account: fmt.Sprintf("spray%d", i),
			IP:      fmt.Sprintf("10.%d.%d.%d", i>>16&0xff, i>>8&0xff, i&0xff),
		})
	}
}

// TestLoginGuard_FullTableStillLocksNewKeys (#2833): once a spray has filled
// the table, a new pair still meets its lockout.
func TestLoginGuard_FullTableStillLocksNewKeys(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	fillGuard(g, 0)
	clock.Advance(time.Second)

	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}
	fail(g, a, 3)
	if got := g.Check(a).RetryAfter; got != time.Minute {
		t.Fatalf("retry after = %v on a full table, want 1m", got)
	}
}

// TestLoginGuard_FullTableKeepsRunningLockouts (#2833): making room in a full
// table drops idle counts, not a lockout that is still running, so a spray
// cannot flush its own lockout away.
func TestLoginGuard_FullTableKeepsRunningLockouts(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}
	fail(g, a, 3)

	fillGuard(g, 0)
	fillGuard(g, ratelimitutil.MaxGuardRecords)
	if got := g.Check(a).RetryAfter; got != time.Minute {
		t.Fatalf("retry after = %v after the spray, want 1m", got)
	}
}

// TestLoginGuard_SweepDropsForgottenRecords: once a record's lockout has run
// out and its failures are older than FailureReset, the next failure anywhere
// drops it, so the table does not grow with every address ever seen.
func TestLoginGuard_SweepDropsForgottenRecords(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)

	fail(g, ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}, 3)
	fail(g, ratelimitutil.LoginAttempt{Account: "guest", IP: "5.6.7.8"}, 1)
	if got := g.Records(); got != 6 {
		t.Fatalf("records = %d, want 6 (a pair, an address and an account per attempt)", got)
	}

	clock.Advance(time.Hour + time.Minute)
	fail(g, ratelimitutil.LoginAttempt{Account: "other", IP: "9.9.9.9"}, 1)
	if got := g.Records(); got != 3 {
		t.Fatalf("records = %d after the reset window, want only the new attempt's 3", got)
	}
}

// TestLoginGuard_BackoffHoldsAtCapForLongRuns: a long run of failures stays at
// MaxLockout instead of doubling past it until time.Duration overflows.
func TestLoginGuard_BackoffHoldsAtCapForLongRuns(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	a := ratelimitutil.LoginAttempt{Account: "admin", IP: "1.2.3.4"}

	fail(g, a, 100)
	if got := g.Check(a).RetryAfter; got != 8*time.Minute {
		t.Fatalf("retry after = %v after 100 failures, want the 8m cap", got)
	}
}

// TestLoginGuard_TableNeverExceedsBound: a spray far past the bound never
// grows the failure table beyond MaxGuardRecords, not even for one attempt.
func TestLoginGuard_TableNeverExceedsBound(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1_000_000, 0)}
	g := newGuard(clock)
	fillGuard(g, 0)
	for i := ratelimitutil.MaxGuardRecords/3 + 1; i < 2*ratelimitutil.MaxGuardRecords/3; i++ {
		g.RecordFailure(ratelimitutil.LoginAttempt{
			Account: fmt.Sprintf("spray%d", i),
			IP:      fmt.Sprintf("10.%d.%d.%d", i>>16&0xff, i>>8&0xff, i&0xff),
		})
		if got := g.Records(); got > ratelimitutil.MaxGuardRecords {
			t.Fatalf("records = %d, over the bound of %d", got, ratelimitutil.MaxGuardRecords)
		}
	}
}
