package authutil_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

const statusTestPhrase = "apple-bread-cloud-delta-eagle-flame"

// mkStatusUser creates an account with password "pw-for-status" and the
// shared test phrase, then moves it to status.
func mkStatusUser(t *testing.T, q *db.Queries, name, status string) {
	t.Helper()
	ctx := context.Background()
	passwordHash, err := authutil.HashPassword("pw-for-status")
	if err != nil {
		t.Fatal(err)
	}
	phraseHash, err := authutil.HashPassword(statusTestPhrase)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := q.CreateUser(ctx, db.CreateUserParams{Username: name, PasswordHash: passwordHash, RecoveryPhraseHash: phraseHash}); err != nil {
		t.Fatalf("create %s: %v", name, err)
	}
	setStatus(t, q, name, authutil.StatusActive, status)
}

func setStatus(t *testing.T, q *db.Queries, name, from, to string) {
	t.Helper()
	if from == to {
		return
	}
	n, err := q.SetUserStatus(context.Background(), db.SetUserStatusParams{Username: name, FromStatus: from, ToStatus: to})
	if err != nil || n != 1 {
		t.Fatalf("set %s %s -> %s: rows=%d err=%v", name, from, to, n, err)
	}
}

// TestLogin_RefusesByStatusAfterPassword checks a pending or disabled account
// with the right password gets its own error, and with a wrong one gets the
// same "invalid credentials" as a stranger, so the status leaks nothing.
func TestLogin_RefusesByStatusAfterPassword(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkStatusUser(t, q, "waiting", authutil.StatusPending)
	mkStatusUser(t, q, "off", authutil.StatusDisabled)
	mkStatusUser(t, q, "on", authutil.StatusActive)

	for _, tc := range []struct {
		user string
		want error
	}{
		{"waiting", authutil.ErrAccountPending},
		{"off", authutil.ErrAccountDisabled},
	} {
		if _, err := authutil.Login(ctx, q, authutil.LoginParams{Username: tc.user, Password: "pw-for-status"}); !errors.Is(err, tc.want) {
			t.Errorf("login %s with the right password = %v, want %v", tc.user, err, tc.want)
		}
		_, err := authutil.Login(ctx, q, authutil.LoginParams{Username: tc.user, Password: "wrong"})
		if err == nil || err.Error() != "invalid credentials" {
			t.Errorf("login %s with a wrong password = %v, want invalid credentials", tc.user, err)
		}
	}
	if _, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "on", Password: "pw-for-status"}); err != nil {
		t.Errorf("active account login: %v", err)
	}
}

// TestSessionsAndBasicAuth_RefuseInactive checks a session issued while the
// account was active stops working once it is disabled, and basic auth refuses
// it too. The app's status call then sees an anonymous caller.
func TestSessionsAndBasicAuth_RefuseInactive(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkStatusUser(t, q, "bob", authutil.StatusActive)
	login, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "bob", Password: "pw-for-status"})
	if err != nil {
		t.Fatal(err)
	}
	setStatus(t, q, "bob", authutil.StatusActive, authutil.StatusDisabled)

	if _, _, err := authutil.ValidateSession(ctx, q, login.SessionToken); err == nil {
		t.Error("a disabled account's session still validates")
	}
	if _, _, err := authutil.ValidateBasicAuth(ctx, q, "bob", "pw-for-status"); !errors.Is(err, authutil.ErrAccountDisabled) {
		t.Errorf("basic auth for a disabled account = %v, want ErrAccountDisabled", err)
	}
	status, err := authutil.GetAuthStatus(ctx, q, authutil.GetAuthStatusParams{SessionToken: login.SessionToken})
	if err != nil {
		t.Fatal(err)
	}
	if status.Authenticated {
		t.Error("auth status treats a disabled account's session as signed in")
	}

	setStatus(t, q, "bob", authutil.StatusDisabled, authutil.StatusActive)
	if _, _, err := authutil.ValidateSession(ctx, q, login.SessionToken); err != nil {
		t.Errorf("re-enabled account's unexpired session: %v", err)
	}
}

// TestRecover_RefusesPending checks the right phrase for a pending account is
// refused with ErrAccountPending and changes nothing.
func TestRecover_RefusesPending(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkStatusUser(t, q, "waiting", authutil.StatusPending)

	_, err := authutil.Recover(ctx, q, authutil.RecoverParams{Username: "waiting", RecoveryPhrase: statusTestPhrase, NewPassword: "a-new-password"})
	if !errors.Is(err, authutil.ErrAccountPending) {
		t.Fatalf("recover pending = %v, want ErrAccountPending", err)
	}
	setStatus(t, q, "waiting", authutil.StatusPending, authutil.StatusActive)
	if _, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "waiting", Password: "pw-for-status"}); err != nil {
		t.Errorf("the refused recover changed the password: %v", err)
	}
}

// TestDemoteFromAdmin_CountsOnlyActiveAdmins checks a disabled admin does not
// stand in for the last active one.
func TestDemoteFromAdmin_CountsOnlyActiveAdmins(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkUser(t, q, "boss", true)
	mkUser(t, q, "sleeping", true)
	setStatus(t, q, "sleeping", authutil.StatusActive, authutil.StatusDisabled)

	if err := authutil.DemoteFromAdmin(ctx, q, "boss"); !errors.Is(err, authutil.ErrLastAdmin) {
		t.Errorf("demote the only active admin = %v, want ErrLastAdmin", err)
	}
}

// TestPromoteToAdmin_OnlyActive checks a pending or disabled account cannot be
// promoted, and neither can a username with no account.
func TestPromoteToAdmin_OnlyActive(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkStatusUser(t, q, "waiting", authutil.StatusPending)
	mkStatusUser(t, q, "off", authutil.StatusDisabled)

	for _, name := range []string{"waiting", "off", "nobody"} {
		if err := authutil.PromoteToAdmin(ctx, q, name); !errors.Is(err, authutil.ErrUserNotFound) {
			t.Errorf("promote %s = %v, want ErrUserNotFound", name, err)
		}
	}
	count, err := q.CountActiveAdmins(ctx)
	if err != nil || count != 0 {
		t.Errorf("active admins = %d (err %v), want 0", count, err)
	}
}

// TestSetup_ValidatesUsername checks the username rule for new accounts. It
// names a folder and a URL segment, so traversal, slashes and a leading dot are
// out.
func TestSetup_ValidatesUsername(t *testing.T) {
	for _, name := range []string{"", "Admin", "../x", "a/b", ".trash", "-dash", "has space", strings.Repeat("a", 33)} {
		t.Run(name, func(t *testing.T) {
			q := newTestDB(t)
			_, err := authutil.Setup(context.Background(), q, authutil.SetupParams{Username: name, Password: "long-enough"})
			if !errors.Is(err, authutil.ErrInvalidUsername) {
				t.Errorf("Setup(%q) = %v, want ErrInvalidUsername", name, err)
			}
		})
	}
	for _, name := range []string{"admin", "j.doe", "a_b-c", "7", strings.Repeat("a", 32)} {
		t.Run(name, func(t *testing.T) {
			q := newTestDB(t)
			if _, err := authutil.Setup(context.Background(), q, authutil.SetupParams{Username: name, Password: "long-enough"}); err != nil {
				t.Errorf("Setup(%q): %v", name, err)
			}
		})
	}
}
