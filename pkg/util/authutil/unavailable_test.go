package authutil_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// TestLookupFailureIsUnavailable is #2858: a credential the database says
// does not exist is a wrong credential, and one it could not be asked about is
// ErrUnavailable, on every check a request's sign-in goes through. The failed
// lookup is not counted toward a lockout, and the session and the account are
// as they were once the database answers again.
func TestLookupFailureIsUnavailable(t *testing.T) {
	ctx := context.Background()
	database := newTestDB(t)
	q := database.Queries
	key := dbtest.AuthKey("mypassword")
	setup, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, Files: vfs.NewMemVFS("files"), Username: "admin", AuthKey: key, SaltSecret: dbtest.SaltSecret})
	if err != nil {
		t.Fatal(err)
	}
	// One miss locks the pair out, so a failed lookup counted as a miss shows.
	guard := ratelimitutil.NewLoginGuard(ratelimitutil.LoginGuardParams{PairThreshold: 1, BaseLockout: time.Minute})

	session := func(token string) error {
		_, _, err := authutil.ValidateSession(ctx, q, token)
		return err
	}
	status := func(token string) (authutil.GetAuthStatusResult, error) {
		return authutil.GetAuthStatus(ctx, q, authutil.GetAuthStatusParams{SessionToken: token})
	}
	reconfirm := func(username string) error {
		_, _, err := authutil.ValidateBasicAuth(ctx, q, username, key)
		return err
	}
	login := func() error {
		_, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "admin", AuthKey: key, SaltSecret: dbtest.SaltSecret, Guard: guard, ClientIP: "1.2.3.4"})
		return err
	}
	basic := func() error {
		_, err := authutil.AuthenticateBasic(ctx, authutil.AuthenticateBasicParams{Queries: q, Username: "admin", Password: key, Guard: guard, ClientIP: "1.2.3.4"})
		return err
	}
	wrong := func(name string, err error) {
		t.Helper()
		if err == nil || errors.Is(err, authutil.ErrUnavailable) {
			t.Errorf("%s = %v, want a wrong credential", name, err)
		}
	}
	unavailable := func(name string, err error) {
		t.Helper()
		if !errors.Is(err, authutil.ErrUnavailable) {
			t.Errorf("%s = %v, want ErrUnavailable", name, err)
		}
	}

	wrong("a token with no session", session("no-such-token"))
	wrong("a username with no account", reconfirm("nobody"))
	if got, err := status("no-such-token"); err != nil || got.Authenticated {
		t.Errorf("status of a token with no session = %+v, %v; want anonymous", got, err)
	}

	restore := dbtest.HideTable(t, database.Db, "sessions")
	unavailable("ValidateSession", session(setup.SessionToken))
	unavailable("ValidateSession of a token with no session", session("no-such-token"))
	_, err = status(setup.SessionToken)
	unavailable("GetAuthStatus", err)
	restore()
	if err := session(setup.SessionToken); err != nil {
		t.Errorf("the session once the database answers: %v", err)
	}

	restore = dbtest.HideTable(t, database.Db, "users")
	unavailable("Login", login())
	unavailable("AuthenticateBasic", basic())
	unavailable("ValidateBasicAuth", reconfirm("admin"))
	restore()
	if err := login(); err != nil {
		t.Errorf("Login once the database answers: %v", err)
	}
	if err := basic(); err != nil {
		t.Errorf("AuthenticateBasic once the database answers: %v", err)
	}
	if err := reconfirm("admin"); err != nil {
		t.Errorf("ValidateBasicAuth once the database answers: %v", err)
	}
}
