package authutil_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// basicAuthFixture is a Quark with one active account, admin/mypassword, and
// a login guard that locks a pair out for a minute after three failures, on a
// clock the test controls.
type basicAuthFixture struct {
	database *db.DatabaseSqlc
	guard    *ratelimitutil.LoginGuard
	now      time.Time
}

func newBasicAuthFixture(t *testing.T) *basicAuthFixture {
	t.Helper()
	f := &basicAuthFixture{database: newTestDB(t), now: time.Unix(1_000_000, 0)}
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: f.database, Files: vfs.NewMemVFS("files"), Username: "admin", AuthKey: dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	f.guard = ratelimitutil.NewLoginGuard(ratelimitutil.LoginGuardParams{Now: func() time.Time { return f.now }, PairThreshold: 3, BaseLockout: time.Minute})
	return f
}

func (f *basicAuthFixture) auth(username, password string) (authutil.AuthenticateBasicResult, error) {
	return authutil.AuthenticateBasic(context.Background(), authutil.AuthenticateBasicParams{
		Queries:  f.database.Queries,
		Username: username,
		Password: password,
		ClientIP: "1.2.3.4",
		Guard:    f.guard,
	})
}

// TestAuthenticateBasic_AcceptsAuthKey: Basic auth takes the account's auth
// key in the password field (#2430), on every request, and names the account.
func TestAuthenticateBasic_AcceptsAuthKey(t *testing.T) {
	f := newBasicAuthFixture(t)
	admin, err := f.database.Queries.GetUserByUsername(context.Background(), "admin")
	if err != nil {
		t.Fatal(err)
	}
	for i := range 3 {
		got, err := f.auth("admin", dbtest.AuthKey("mypassword"))
		if err != nil {
			t.Fatalf("request %d: %v", i, err)
		}
		if got.Username != "admin" || got.UserID != admin.ID {
			t.Fatalf("request %d: got %+v", i, got)
		}
	}
	for _, c := range [][2]string{{"admin", dbtest.AuthKey("wrong")}, {"admin", ""}, {"ghost", dbtest.AuthKey("mypassword")}} {
		if _, err := f.auth(c[0], c[1]); err == nil || err.Error() != "invalid credentials" {
			t.Errorf("%s/%q: %v, want invalid credentials", c[0], c[1], err)
		}
	}
}

// TestAuthenticateBasic_KeyChangeTakesEffectAtOnce: nothing is remembered
// between requests, so the old key stops working the moment it is replaced.
func TestAuthenticateBasic_KeyChangeTakesEffectAtOnce(t *testing.T) {
	f := newBasicAuthFixture(t)
	if _, err := f.auth("admin", dbtest.AuthKey("mypassword")); err != nil {
		t.Fatal(err)
	}
	user, err := f.database.Queries.GetUserByUsername(context.Background(), "admin")
	if err != nil {
		t.Fatal(err)
	}
	hash, err := authutil.HashKey(dbtest.AuthKey("newpassword"))
	if err != nil {
		t.Fatal(err)
	}
	if err := f.database.Queries.SetUserCredentials(context.Background(), db.SetUserCredentialsParams{ID: user.ID, AuthKeyHash: hash, AuthSalt: user.AuthSalt}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.auth("admin", dbtest.AuthKey("mypassword")); err == nil {
		t.Fatal("old key admitted after a key change")
	}
	if _, err := f.auth("admin", dbtest.AuthKey("newpassword")); err != nil {
		t.Fatalf("new key: %v", err)
	}
}

// TestAuthenticateBasic_PendingDisabledOrDeletedRejected: an account that is
// not active is refused, by name only to someone who has its key.
func TestAuthenticateBasic_PendingDisabledOrDeletedRejected(t *testing.T) {
	ctx := context.Background()
	f := newBasicAuthFixture(t)
	queries := f.database.Queries
	if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: f.database, Files: vfs.NewMemVFS("files"), Username: "bob", AuthKey: dbtest.AuthKey("bob-password"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	admin, err := queries.GetUserByUsername(ctx, "admin")
	if err != nil {
		t.Fatal(err)
	}
	bob := func() error {
		_, err := f.auth("bob", dbtest.AuthKey("bob-password"))
		return err
	}
	if err := bob(); err != nil {
		t.Fatal(err)
	}

	setStatus(t, queries, "bob", authutil.StatusActive, authutil.StatusPending)
	if err := bob(); !errors.Is(err, authutil.ErrAccountPending) {
		t.Errorf("pending account: %v, want ErrAccountPending", err)
	}
	if _, err := f.auth("bob", dbtest.AuthKey("wrong")); err == nil || errors.Is(err, authutil.ErrAccountPending) {
		t.Errorf("pending account, wrong key: %v, want invalid credentials", err)
	}
	setStatus(t, queries, "bob", authutil.StatusPending, authutil.StatusActive)

	if _, err := authutil.DisableUser(ctx, authutil.DisableUserParams{Database: f.database, Username: "bob", ActorUserID: admin.ID}); err != nil {
		t.Fatal(err)
	}
	if err := bob(); !errors.Is(err, authutil.ErrAccountDisabled) {
		t.Fatalf("disabled account: %v, want ErrAccountDisabled", err)
	}
	if _, err := authutil.EnableUser(ctx, queries, authutil.EnableUserParams{Username: "bob"}); err != nil {
		t.Fatal(err)
	}
	if err := bob(); err != nil {
		t.Fatalf("re-enabled account: %v", err)
	}
	if _, err := authutil.DeleteUser(ctx, authutil.DeleteUserParams{Database: f.database, Username: "bob", ActorUserID: admin.ID}); err != nil {
		t.Fatal(err)
	}
	if err := bob(); err == nil {
		t.Fatal("deleted account admitted")
	}
}

// TestAuthenticateBasic_LockoutEnforced: wrong keys count toward the login
// guard, a lockout refuses even the right key until it lifts, and a success
// clears the count, as at sign-in (#2765).
func TestAuthenticateBasic_LockoutEnforced(t *testing.T) {
	f := newBasicAuthFixture(t)
	if _, err := f.auth("admin", dbtest.AuthKey("mypassword")); err != nil {
		t.Fatal(err)
	}
	for range 3 {
		if _, err := f.auth("admin", dbtest.AuthKey("wrong")); err == nil || err.Error() != "invalid credentials" {
			t.Fatalf("wrong key: %v", err)
		}
	}
	var locked *authutil.TooManyAttemptsError
	if _, err := f.auth("admin", dbtest.AuthKey("mypassword")); !errors.As(err, &locked) || locked.RetryAfter != time.Minute {
		t.Fatalf("right key during lockout: %v, want TooManyAttemptsError", err)
	}
	f.now = f.now.Add(time.Minute)
	if _, err := f.auth("admin", dbtest.AuthKey("mypassword")); err != nil {
		t.Fatalf("after lockout: %v", err)
	}
	// The success cleared the pair, so three fresh misses are needed again.
	for range 2 {
		_, _ = f.auth("admin", dbtest.AuthKey("wrong"))
	}
	if _, err := f.auth("admin", dbtest.AuthKey("mypassword")); err != nil {
		t.Fatalf("locked again before the threshold: %v", err)
	}
}

// TestAuthenticateBasic_UnknownUsernameLocksOutAlike: guesses at a username
// that does not exist are counted too, so a lockout says nothing about which
// accounts are real.
func TestAuthenticateBasic_UnknownUsernameLocksOutAlike(t *testing.T) {
	f := newBasicAuthFixture(t)
	for range 3 {
		if _, err := f.auth("ghost", dbtest.AuthKey("wrong")); err == nil || err.Error() != "invalid credentials" {
			t.Fatalf("unknown username: %v", err)
		}
	}
	var locked *authutil.TooManyAttemptsError
	if _, err := f.auth("ghost", dbtest.AuthKey("wrong")); !errors.As(err, &locked) {
		t.Fatalf("unknown username was never locked out: %v", err)
	}
}

// TestAuthenticateBasic_RawPasswordNotCounted: a raw password is an app too
// old to send the key (#2430). It is refused before the guard and never counts
// toward a lockout, and it is refused the same way during one.
func TestAuthenticateBasic_RawPasswordNotCounted(t *testing.T) {
	f := newBasicAuthFixture(t)
	for range 5 {
		if _, err := f.auth("admin", "mypassword"); !errors.Is(err, authutil.ErrAppTooOld) {
			t.Fatalf("raw password: %v, want ErrAppTooOld", err)
		}
	}
	if _, err := f.auth("admin", dbtest.AuthKey("mypassword")); err != nil {
		t.Fatalf("the key after five raw passwords: %v", err)
	}
	for range 3 {
		_, _ = f.auth("admin", dbtest.AuthKey("wrong"))
	}
	if _, err := f.auth("admin", "mypassword"); !errors.Is(err, authutil.ErrAppTooOld) {
		t.Errorf("raw password during lockout: %v, want ErrAppTooOld", err)
	}
}

// TestAuthenticateBasic_NilGuardChecksEveryTime: without a guard nothing is
// locked out, and every key is still checked.
func TestAuthenticateBasic_NilGuardChecksEveryTime(t *testing.T) {
	f := newBasicAuthFixture(t)
	f.guard = nil
	for range 5 {
		if _, err := f.auth("admin", dbtest.AuthKey("wrong")); err == nil {
			t.Fatal("wrong key admitted without a guard")
		}
	}
	if _, err := f.auth("admin", dbtest.AuthKey("mypassword")); err != nil {
		t.Fatal(err)
	}
}
