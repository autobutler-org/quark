package authutil_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
)

// TestLogin_GuardLocksOutAfterFailures: once an address has missed the
// threshold, even the right password is refused with the time to wait, and
// the lockout lifts when that time has passed (#1861).
func TestLogin_GuardLocksOutAfterFailures(t *testing.T) {
	ctx := context.Background()
	database := newTestDB(t)
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", AuthKey: dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_000_000, 0)
	guard := ratelimitutil.NewLoginGuard(ratelimitutil.LoginGuardParams{Now: func() time.Time { return now }, PairThreshold: 3, BaseLockout: time.Minute})
	login := func(password string) error {
		_, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "admin", AuthKey: dbtest.AuthKey(password), Guard: guard, ClientIP: "1.2.3.4"})
		return err
	}

	for range 3 {
		if err := login("wrong"); err == nil || err.Error() != "invalid credentials" {
			t.Fatalf("wrong password: %v", err)
		}
	}
	var locked *authutil.TooManyAttemptsError
	if err := login("mypassword"); !errors.As(err, &locked) || locked.RetryAfter != time.Minute {
		t.Fatalf("right password during lockout: %v", err)
	}

	now = now.Add(time.Minute)
	if err := login("mypassword"); err != nil {
		t.Fatalf("right password after lockout: %v", err)
	}
	// The success cleared the pair, so three fresh misses are needed again.
	for range 2 {
		_ = login("wrong")
	}
	if err := login("mypassword"); err != nil {
		t.Fatalf("locked again before the threshold: %v", err)
	}
}

// TestLogin_GuardTreatsUnknownUsernamesAlike: guessing at a username that
// does not exist locks out exactly like guessing at one that does, so the
// lockout reveals nothing about which accounts are real.
func TestLogin_GuardTreatsUnknownUsernamesAlike(t *testing.T) {
	ctx := context.Background()
	database := newTestDB(t)
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", AuthKey: dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_000_000, 0)
	guard := ratelimitutil.NewLoginGuard(ratelimitutil.LoginGuardParams{Now: func() time.Time { return now }, PairThreshold: 3, BaseLockout: time.Minute})

	var errs []error
	for _, username := range []string{"admin", "ghost"} {
		for range 4 {
			_, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: username, AuthKey: dbtest.AuthKey("wrong"), Guard: guard, ClientIP: "1.2.3.4"})
			errs = append(errs, err)
		}
	}
	for i, err := range errs {
		if err == nil || err.Error() != errs[i%4].Error() {
			t.Fatalf("attempt %d: %v, want the same answer as attempt %d (%v)", i, err, i%4, errs[i%4])
		}
	}
	var locked *authutil.TooManyAttemptsError
	if !errors.As(errs[7], &locked) {
		t.Fatalf("unknown username was never locked out: %v", errs[7])
	}
}
