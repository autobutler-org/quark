package v0_auth_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestDeleteAccount_LastAdminRules drives account=true from the only active
// admin (#1909): refused with 409 while another account remains, touching
// nothing, not even the caller's session; accepted when only a pending request
// remains, which goes too and returns the Quark to setup.
func TestDeleteAccount_LastAdminRules(t *testing.T) {
	addOther := func(t *testing.T, queries *db.Queries, status string) {
		t.Helper()
		ctx := context.Background()
		hash, err := authutil.HashPassword("OtherPassword123!")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := queries.CreateUser(ctx, db.CreateUserParams{Username: "other-user", PasswordHash: hash, RecoveryPhraseHash: hash}); err != nil {
			t.Fatal(err)
		}
		if status != authutil.StatusActive {
			if _, err := queries.SetUserStatus(ctx, db.SetUserStatusParams{Username: "other-user", FromStatus: authutil.StatusActive, ToStatus: status}); err != nil {
				t.Fatal(err)
			}
		}
	}

	t.Run("another account remains", func(t *testing.T) {
		engine, sqlDB, _ := newDeleteAccountEngine(t)
		addOther(t, db.New(sqlDB), authutil.StatusActive)
		before := sessionCount(t, sqlDB)

		w := deleteAccountRequest(engine, "account=true&confirm="+deleteAccountUser)
		if w.Code != http.StatusConflict {
			t.Fatalf("expected 409, got %d: %s", w.Code, w.Body.String())
		}
		if got := decodeBody(t, w)["error"]; got != authutil.ErrLastAdmin.Error() {
			t.Errorf("error = %v, want %q", got, authutil.ErrLastAdmin.Error())
		}
		if userCount(t, sqlDB) != 2 {
			t.Error("a refused delete removed an account")
		}
		if sessionCount(t, sqlDB) != before {
			t.Error("a refused delete signed the caller out")
		}
	})

	t.Run("only a pending request remains", func(t *testing.T) {
		engine, sqlDB, _ := newDeleteAccountEngine(t)
		addOther(t, db.New(sqlDB), authutil.StatusPending)

		w := deleteAccountRequest(engine, "account=true&confirm="+deleteAccountUser)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		if userCount(t, sqlDB) != 0 {
			t.Errorf("expected no accounts left, got %d", userCount(t, sqlDB))
		}
		if !decodeFilesRetained(t, w) {
			t.Error("filesRetained should be true: the files outlived the last account")
		}
	})
}
