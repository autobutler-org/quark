package authutil_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// mkUser inserts a user and optionally promotes them to admin.
func mkUser(t *testing.T, q *db.Queries, name string, admin bool) {
	t.Helper()
	hash, err := authutil.HashPassword("pw")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if _, err := q.CreateUser(context.Background(), db.CreateUserParams{
		Username:           name,
		PasswordHash:       hash,
		RecoveryPhraseHash: hash,
	}); err != nil {
		t.Fatalf("create %s: %v", name, err)
	}
	if admin {
		if err := authutil.PromoteToAdmin(context.Background(), q, name); err != nil {
			t.Fatalf("promote %s: %v", name, err)
		}
	}
}

func TestIsAdmin(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkUser(t, q, "boss", true)
	mkUser(t, q, "peon", false)

	for _, tc := range []struct {
		name, user string
		want       bool
	}{
		{"admin user", "boss", true},
		{"non-admin user", "peon", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := authutil.IsAdmin(ctx, q, tc.user)
			if err != nil {
				t.Fatalf("IsAdmin: %v", err)
			}
			if got != tc.want {
				t.Errorf("IsAdmin(%q) = %v, want %v", tc.user, got, tc.want)
			}
		})
	}
}

// TestIsAdmin_UnknownUser pins the actual behavior for a username with no row.
//
// The doc comment claims "Returns false (not an error) for unknown users", but
// IsUserAdmin is a sqlc :one query, so a missing row yields sql.ErrNoRows and
// IsAdmin wraps it. The (false, err) result is safe — RequireAdmin treats any
// error as "not admin" — but the documented contract is wrong. This test
// records reality so a future change to either side is deliberate.
func TestIsAdmin_UnknownUser(t *testing.T) {
	q := newTestDB(t)
	got, err := authutil.IsAdmin(context.Background(), q, "ghost")
	if got {
		t.Error("unknown user must never be reported as admin")
	}
	if err == nil {
		t.Error("documented as returning no error, but currently errors — " +
			"if this now passes, the doc comment matches and this test should be updated")
	} else if !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("expected wrapped sql.ErrNoRows, got %v", err)
	}
}

func TestPromoteToAdmin_Idempotent(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkUser(t, q, "u", false)

	for i := 0; i < 2; i++ {
		if err := authutil.PromoteToAdmin(ctx, q, "u"); err != nil {
			t.Fatalf("promote #%d: %v", i+1, err)
		}
	}
	isAdmin, err := authutil.IsAdmin(ctx, q, "u")
	if err != nil || !isAdmin {
		t.Errorf("expected admin after repeated promote, got %v (err %v)", isAdmin, err)
	}
	count, err := q.CountActiveAdmins(ctx)
	if err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Errorf("expected 1 admin, got %d", count)
	}
}

func TestDemoteFromAdmin_RefusesLastAdmin(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkUser(t, q, "only", true)

	err := authutil.DemoteFromAdmin(ctx, q, "only")
	if err == nil {
		t.Fatal("expected demoting the last admin to fail")
	}
	// The account must still be admin — a refused demote may not partially apply.
	isAdmin, checkErr := authutil.IsAdmin(ctx, q, "only")
	if checkErr != nil {
		t.Fatalf("IsAdmin: %v", checkErr)
	}
	if !isAdmin {
		t.Error("refused demote still removed admin — lockout")
	}
}

func TestDemoteFromAdmin_AllowsWhenAnotherAdminExists(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkUser(t, q, "a", true)
	mkUser(t, q, "b", true)

	if err := authutil.DemoteFromAdmin(ctx, q, "a"); err != nil {
		t.Fatalf("demote with 2 admins should succeed: %v", err)
	}
	isAdmin, err := authutil.IsAdmin(ctx, q, "a")
	if err != nil {
		t.Fatalf("IsAdmin: %v", err)
	}
	if isAdmin {
		t.Error("expected 'a' to be demoted")
	}
	count, err := q.CountActiveAdmins(ctx)
	if err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Errorf("expected 1 admin remaining, got %d", count)
	}
}

// TestDemoteFromAdmin_NonAdminTargetBlockedByGuard documents a real bug.
//
// The last-admin guard counts ALL admins but never checks whether the TARGET is
// one. With exactly one admin and a separate non-admin user, demoting the
// NON-ADMIN is rejected with "cannot demote the last admin" — a confusing error
// about an account the caller did not name, for an operation that would not have
// changed the admin count at all.
//
// The guard should compare against the target's own admin status, e.g. refuse
// only when the target is an admin AND the count is 1.
func TestDemoteFromAdmin_NonAdminTargetBlockedByGuard(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkUser(t, q, "boss", true)
	mkUser(t, q, "peon", false)

	err := authutil.DemoteFromAdmin(ctx, q, "peon")
	if err == nil {
		t.Skip("guard now checks the target — bug fixed, update this test")
	}
	if !errors.Is(err, authutil.ErrLastAdmin) {
		t.Fatalf("unexpected error: %v", err)
	}
	t.Logf("KNOWN BUG: demoting non-admin %q rejected with %q", "peon", err)

	// The admin count is untouched, confirming the operation was a no-op that
	// still reported failure.
	count, cErr := q.CountActiveAdmins(ctx)
	if cErr != nil {
		t.Fatalf("count: %v", cErr)
	}
	if count != 1 {
		t.Errorf("admin count should be 1, got %d", count)
	}
}

// TestDemoteFromAdmin_UnknownUserSucceedsSilently records that demoting a
// username with no row reports success. Callers get 200 for a user that does
// not exist, which is misleading for an admin UI.
func TestDemoteFromAdmin_UnknownUserSucceedsSilently(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	mkUser(t, q, "boss", true)
	mkUser(t, q, "second", true)

	err := authutil.DemoteFromAdmin(ctx, q, "does-not-exist")
	if err != nil {
		t.Logf("demote of unknown user returned: %v", err)
	}
	count, cErr := q.CountActiveAdmins(ctx)
	if cErr != nil {
		t.Fatalf("count: %v", cErr)
	}
	if count != 2 {
		t.Errorf("admin count must be unchanged at 2, got %d", count)
	}
}
