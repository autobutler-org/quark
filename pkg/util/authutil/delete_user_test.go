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

func grantRow(t *testing.T, q *db.Queries, userID int64, rel, level string) {
	t.Helper()
	if err := q.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: rel, UserID: sql.NullInt64{Int64: userID, Valid: true}, Level: level,
	}); err != nil {
		t.Fatalf("grant %s %s: %v", rel, level, err)
	}
}

// levels maps each path a user has a direct row on to that row's level.
func levels(t *testing.T, database *db.DatabaseSqlc, userID int64) map[string]string {
	t.Helper()
	rows, err := database.Db.Query(`SELECT rel_path, level FROM path_access WHERE user_id = ?`, userID)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	got := map[string]string{}
	for rows.Next() {
		var rel, level string
		if err := rows.Scan(&rel, &level); err != nil {
			t.Fatal(err)
		}
		got[rel] = level
	}
	return got
}

func count(t *testing.T, database *db.DatabaseSqlc, query string, args ...any) int {
	t.Helper()
	var n int
	if err := database.Db.QueryRow(query, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// TestDeleteUser_ReassignsOwnerRowsToActor checks an admin's delete hands every
// owned path to that admin, including one in the trash and one the admin
// already had a row on, and drops the account's other rows, group memberships,
// sessions and row.
func TestDeleteUser_ReassignsOwnerRowsToActor(t *testing.T) {
	database := dbtest.NewDB(t)
	q := database.Queries
	ctx := context.Background()
	setupFounder(t, q)
	mkStatusUser(t, q, "bob", authutil.StatusActive)
	adminID, bobID := userID(t, q, "admin"), userID(t, q, "bob")

	grantRow(t, q, bobID, "bob", "owner")
	grantRow(t, q, bobID, ".trash/20260914-1/report.txt", "owner")
	grantRow(t, q, bobID, "shared", "owner")
	grantRow(t, q, adminID, "shared", "read")
	grantRow(t, q, bobID, "family", "read")
	grantRow(t, q, bobID, "projects", "write")
	if _, err := database.Db.Exec(`INSERT INTO groups (name) VALUES ('kids')`); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Db.Exec(`INSERT INTO group_members (group_id, user_id) SELECT id, ? FROM groups WHERE name = 'kids'`, bobID); err != nil {
		t.Fatal(err)
	}
	if _, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "bob", Password: "pw-for-status"}); err != nil {
		t.Fatal(err)
	}

	result, err := authutil.DeleteUser(ctx, authutil.DeleteUserParams{Database: database, ActorUserID: adminID, Username: "bob"})
	if err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}
	if result.HeirUserID != adminID || result.OwnerRowsReassigned != 3 || result.SetupReset {
		t.Errorf("result = %+v, want heir %d, 3 reassigned, no reset", result, adminID)
	}
	want := map[string]string{"bob": "owner", ".trash/20260914-1/report.txt": "owner", "shared": "owner"}
	got := levels(t, database, adminID)
	if len(got) != len(want) {
		t.Errorf("admin's rows = %v, want %v", got, want)
	}
	for rel, level := range want {
		if got[rel] != level {
			t.Errorf("admin's %s = %q, want %q", rel, got[rel], level)
		}
	}
	for what, query := range map[string]string{
		"access rows":       `SELECT COUNT(*) FROM path_access WHERE user_id = ?`,
		"group memberships": `SELECT COUNT(*) FROM group_members WHERE user_id = ?`,
		"sessions":          `SELECT COUNT(*) FROM sessions WHERE user_id = ?`,
		"account row":       `SELECT COUNT(*) FROM users WHERE id = ?`,
	} {
		if n := count(t, database, query, bobID); n != 0 {
			t.Errorf("deleted account left %d %s", n, what)
		}
	}
}

// TestDeleteUser_SelfServiceHeirIsOldestActiveAdmin checks an account deleting
// itself hands its paths to the longest-standing admin that is still active,
// skipping one that is turned off.
func TestDeleteUser_SelfServiceHeirIsOldestActiveAdmin(t *testing.T) {
	database := dbtest.NewDB(t)
	q := database.Queries
	ctx := context.Background()
	setupFounder(t, q)
	mkUser(t, q, "deputy", true)
	mkStatusUser(t, q, "bob", authutil.StatusActive)
	setStatus(t, q, "admin", authutil.StatusActive, authutil.StatusDisabled)
	deputyID, bobID := userID(t, q, "deputy"), userID(t, q, "bob")
	grantRow(t, q, bobID, "bob", "owner")

	result, err := authutil.DeleteUser(ctx, authutil.DeleteUserParams{Database: database, Username: "bob"})
	if err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}
	if result.HeirUserID != deputyID || result.OwnerRowsReassigned != 1 {
		t.Errorf("result = %+v, want heir deputy (%d) with 1 row", result, deputyID)
	}
	if got := levels(t, database, deputyID); got["bob"] != "owner" {
		t.Errorf("deputy's rows = %v, want owner of bob", got)
	}
}

// TestDeleteUser_LastAdminRules checks the only active admin deleting
// themselves: refused while an active or disabled account remains, and allowed
// when only pending requests remain, which go too and return the Quark to
// setup.
func TestDeleteUser_LastAdminRules(t *testing.T) {
	for _, other := range []string{authutil.StatusActive, authutil.StatusDisabled} {
		t.Run("with an "+other+" account", func(t *testing.T) {
			database := dbtest.NewDB(t)
			q := database.Queries
			setupFounder(t, q)
			mkStatusUser(t, q, "member", other)

			_, err := authutil.DeleteUser(context.Background(), authutil.DeleteUserParams{Database: database, Username: "admin"})
			if !errors.Is(err, authutil.ErrLastAdmin) {
				t.Fatalf("DeleteUser = %v, want ErrLastAdmin", err)
			}
			if n := count(t, database, `SELECT COUNT(*) FROM users`); n != 2 {
				t.Errorf("refused delete left %d accounts, want 2", n)
			}
		})
	}

	t.Run("with only pending requests", func(t *testing.T) {
		database := dbtest.NewDB(t)
		q := database.Queries
		ctx := context.Background()
		setupFounder(t, q)
		mkStatusUser(t, q, "asker", authutil.StatusPending)

		result, err := authutil.DeleteUser(ctx, authutil.DeleteUserParams{Database: database, Username: "admin"})
		if err != nil {
			t.Fatalf("DeleteUser: %v", err)
		}
		if !result.SetupReset || result.HeirUserID != 0 {
			t.Errorf("result = %+v, want a setup reset with no heir", result)
		}
		if complete, _ := authutil.IsSetupComplete(ctx, q); complete {
			t.Error("the Quark did not return to setup")
		}
	})

	t.Run("with a second active admin", func(t *testing.T) {
		database := dbtest.NewDB(t)
		q := database.Queries
		setupFounder(t, q)
		mkUser(t, q, "deputy", true)

		result, err := authutil.DeleteUser(context.Background(), authutil.DeleteUserParams{Database: database, Username: "admin"})
		if err != nil {
			t.Fatalf("DeleteUser: %v", err)
		}
		if result.HeirUserID != userID(t, q, "deputy") || result.SetupReset {
			t.Errorf("result = %+v, want deputy as heir and no reset", result)
		}
	})
}

// TestDeleteUser_AdminRefusals checks an admin cannot delete their own account
// through the admin path, and an unknown username is ErrUserNotFound.
func TestDeleteUser_AdminRefusals(t *testing.T) {
	database := dbtest.NewDB(t)
	q := database.Queries
	ctx := context.Background()
	setupFounder(t, q)
	mkUser(t, q, "deputy", true)
	adminID := userID(t, q, "admin")

	if _, err := authutil.DeleteUser(ctx, authutil.DeleteUserParams{Database: database, ActorUserID: adminID, Username: "admin"}); !errors.Is(err, authutil.ErrSelfAction) {
		t.Errorf("delete self = %v, want ErrSelfAction", err)
	}
	if _, err := authutil.DeleteUser(ctx, authutil.DeleteUserParams{Database: database, ActorUserID: adminID, Username: "nobody"}); !errors.Is(err, authutil.ErrUserNotFound) {
		t.Errorf("delete unknown = %v, want ErrUserNotFound", err)
	}
}
