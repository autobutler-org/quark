package authutil_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

func userID(t *testing.T, q *db.Queries, name string) int64 {
	t.Helper()
	user, err := q.GetUserByUsername(context.Background(), name)
	if err != nil {
		t.Fatalf("look up %s: %v", name, err)
	}
	return user.ID
}

// TestDisableUser_EndsSessionsAndKeepsOwnership checks turning an account off
// ends its sessions and refuses its sign-in, leaves everyone else signed in,
// keeps its access rows, and that turning it back on restores sign-in.
func TestDisableUser_EndsSessionsAndKeepsOwnership(t *testing.T) {
	database := dbtest.NewDB(t)
	q := database.Queries
	ctx := context.Background()
	setupFounder(t, database, t.TempDir())
	mkStatusUser(t, q, "bob", authutil.StatusActive)
	adminID, bobID := userID(t, q, "admin"), userID(t, q, "bob")

	bobLogin, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "bob", Password: "pw-for-status"})
	if err != nil {
		t.Fatal(err)
	}
	adminLogin, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "admin", Password: "admin-password"})
	if err != nil {
		t.Fatal(err)
	}
	if err := q.SetUserPathAccess(ctx, db.SetUserPathAccessParams{RelPath: "bob", UserID: sql.NullInt64{Int64: bobID, Valid: true}, Level: "owner"}); err != nil {
		t.Fatal(err)
	}

	if _, err := authutil.DisableUser(ctx, authutil.DisableUserParams{Database: database, ActorUserID: adminID, Username: "bob"}); err != nil {
		t.Fatalf("DisableUser: %v", err)
	}
	if sessions, _ := q.ListActiveSessionsForUser(ctx, bobID); len(sessions) != 0 {
		t.Errorf("disabled account kept %d sessions", len(sessions))
	}
	if _, _, err := authutil.ValidateSession(ctx, q, bobLogin.SessionToken); err == nil {
		t.Error("disabled account's session still validates")
	}
	if _, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "bob", Password: "pw-for-status"}); !errors.Is(err, authutil.ErrAccountDisabled) {
		t.Errorf("login after disable = %v, want ErrAccountDisabled", err)
	}
	if _, _, err := authutil.ValidateSession(ctx, q, adminLogin.SessionToken); err != nil {
		t.Errorf("the admin's session ended too: %v", err)
	}
	if active, err := authutil.IsActive(ctx, q, bobID); err != nil || active {
		t.Errorf("IsActive(disabled) = %v, %v", active, err)
	}
	rows, err := q.ListPathAccessForUser(ctx, sql.NullInt64{Int64: bobID, Valid: true})
	if err != nil || len(rows) != 1 {
		t.Errorf("disabled account's access rows = %v, %v; want its owner row kept", rows, err)
	}
	if _, err := authutil.DisableUser(ctx, authutil.DisableUserParams{Database: database, ActorUserID: adminID, Username: "bob"}); !errors.Is(err, authutil.ErrUserNotFound) {
		t.Errorf("disable twice = %v, want ErrUserNotFound", err)
	}

	if _, err := authutil.EnableUser(ctx, q, authutil.EnableUserParams{Username: "bob"}); err != nil {
		t.Fatalf("EnableUser: %v", err)
	}
	if _, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "bob", Password: "pw-for-status"}); err != nil {
		t.Errorf("login after enable: %v", err)
	}
	if _, err := authutil.EnableUser(ctx, q, authutil.EnableUserParams{Username: "bob"}); !errors.Is(err, authutil.ErrUserNotFound) {
		t.Errorf("enable an active account = %v, want ErrUserNotFound", err)
	}
	if active, err := authutil.IsActive(ctx, q, 9999); err != nil || active {
		t.Errorf("IsActive(missing) = %v, %v; want false, nil", active, err)
	}
}

// TestDisableUser_Refusals checks an admin cannot turn off their own account,
// an account that is not active cannot be turned off, and the only active
// admin cannot be turned off until a second one exists.
func TestDisableUser_Refusals(t *testing.T) {
	database := dbtest.NewDB(t)
	q := database.Queries
	ctx := context.Background()
	setupFounder(t, database, t.TempDir())
	mkStatusUser(t, q, "member", authutil.StatusActive)
	mkStatusUser(t, q, "waiting", authutil.StatusPending)
	adminID, memberID := userID(t, q, "admin"), userID(t, q, "member")
	disable := func(actor int64, username string) error {
		_, err := authutil.DisableUser(ctx, authutil.DisableUserParams{Database: database, ActorUserID: actor, Username: username})
		return err
	}

	if err := disable(adminID, "admin"); !errors.Is(err, authutil.ErrSelfAction) {
		t.Errorf("disable self = %v, want ErrSelfAction", err)
	}
	for _, name := range []string{"nobody", "waiting"} {
		if err := disable(adminID, name); !errors.Is(err, authutil.ErrUserNotFound) {
			t.Errorf("disable %s = %v, want ErrUserNotFound", name, err)
		}
	}
	if err := disable(memberID, "admin"); !errors.Is(err, authutil.ErrLastAdmin) {
		t.Errorf("disable the only active admin = %v, want ErrLastAdmin", err)
	}
	if active, _ := authutil.IsActive(ctx, q, adminID); !active {
		t.Fatal("a refused disable turned the admin off")
	}

	mkUser(t, q, "deputy", true)
	if err := disable(memberID, "admin"); err != nil {
		t.Errorf("disable an admin with another active admin: %v", err)
	}
}
