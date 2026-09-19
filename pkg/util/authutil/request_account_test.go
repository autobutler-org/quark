package authutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// setupFounder sets a Quark up with the founding admin, whose home lands in
// filesDir like every other account's (#1908).
func setupFounder(t *testing.T, database *db.DatabaseSqlc, filesDir string) {
	t.Helper()
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{
		Database: database,
		Username: "admin",
		Password: "admin-password",
		FilesDir: filesDir,
	}); err != nil {
		t.Fatal(err)
	}
}

func request(q *db.Queries, username, password string) (authutil.RequestAccountResult, error) {
	return authutil.RequestAccount(context.Background(), q, authutil.RequestAccountParams{
		Username:        username,
		Password:        password,
		RequestsEnabled: true,
	})
}

// TestRequestAccount_RefusedWhenOffOrBeforeSetup checks a request is refused
// while the toggle is off and on a Quark nobody has set up, and that the
// refusal leaves no row that would count as setup.
func TestRequestAccount_RefusedWhenOffOrBeforeSetup(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()

	if _, err := request(q, "bob", "bob-password"); !errors.Is(err, authutil.ErrAccessRequestsOff) {
		t.Errorf("request before setup = %v, want ErrAccessRequestsOff", err)
	}
	if complete, _ := authutil.IsSetupComplete(ctx, q); complete {
		t.Fatal("a refused request completed setup")
	}

	setupFounder(t, database, t.TempDir())
	_, err := authutil.RequestAccount(ctx, q, authutil.RequestAccountParams{Username: "bob", Password: "bob-password"})
	if !errors.Is(err, authutil.ErrAccessRequestsOff) {
		t.Errorf("request with requests off = %v, want ErrAccessRequestsOff", err)
	}
}

// TestRequestAccount_PendingUntilApproved walks a request from submission to
// sign-in: pending and refused, approved, then signing in with the password
// and recovering with the phrase the request returned.
func TestRequestAccount_PendingUntilApproved(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	setupFounder(t, database, t.TempDir())

	result, err := request(q, "bob", "bob-password")
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	if result.RecoveryPhrase == "" {
		t.Fatal("request returned no recovery phrase")
	}
	user, err := q.GetUserByUsername(ctx, "bob")
	if err != nil {
		t.Fatal(err)
	}
	if user.Status != authutil.StatusPending || user.IsAdmin != 0 {
		t.Errorf("requested account status=%q admin=%d, want pending non-admin", user.Status, user.IsAdmin)
	}
	if _, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "bob", Password: "bob-password"}); !errors.Is(err, authutil.ErrAccountPending) {
		t.Errorf("login while pending = %v, want ErrAccountPending", err)
	}

	if _, err := authutil.ApproveRequest(ctx, authutil.ApproveRequestParams{
		Database: database,
		Username: "bob",
		FilesDir: t.TempDir(),
	}); err != nil {
		t.Fatalf("approve: %v", err)
	}
	if _, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "bob", Password: "bob-password"}); err != nil {
		t.Errorf("login after approval: %v", err)
	}
	if _, err := authutil.Recover(ctx, q, authutil.RecoverParams{Username: "bob", RecoveryPhrase: result.RecoveryPhrase, NewPassword: "new-bob-password"}); err != nil {
		t.Errorf("recover with the request's phrase: %v", err)
	}
	if _, err := authutil.ApproveRequest(ctx, authutil.ApproveRequestParams{
		Database: database,
		Username: "bob",
		FilesDir: t.TempDir(),
	}); !errors.Is(err, authutil.ErrRequestNotFound) {
		t.Errorf("approve an active account = %v, want ErrRequestNotFound", err)
	}
}

// TestRequestAccount_TakenAndDenied checks a username held by an account or a
// pending request is taken, a denial frees it at once, and deny touches only
// pending requests.
func TestRequestAccount_TakenAndDenied(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	setupFounder(t, database, t.TempDir())

	if _, err := request(q, "admin", "whatever-password"); !errors.Is(err, authutil.ErrUsernameTaken) {
		t.Errorf("request an existing account's name = %v, want ErrUsernameTaken", err)
	}
	if _, err := request(q, "bob", "bob-password"); err != nil {
		t.Fatal(err)
	}
	if _, err := request(q, "bob", "other-password"); !errors.Is(err, authutil.ErrUsernameTaken) {
		t.Errorf("request a pending name = %v, want ErrUsernameTaken", err)
	}

	if _, err := authutil.DenyRequest(ctx, q, authutil.DenyRequestParams{Username: "bob"}); err != nil {
		t.Fatalf("deny: %v", err)
	}
	if _, err := request(q, "bob", "other-password"); err != nil {
		t.Errorf("request a denied name again: %v", err)
	}
	if _, err := authutil.DenyRequest(ctx, q, authutil.DenyRequestParams{Username: "admin"}); !errors.Is(err, authutil.ErrRequestNotFound) {
		t.Errorf("deny an active account = %v, want ErrRequestNotFound", err)
	}
	if _, err := q.GetUserByUsername(ctx, "admin"); err != nil {
		t.Errorf("deny removed an active account: %v", err)
	}
}

// TestRequestAccount_Validation checks the username rule and password length.
func TestRequestAccount_Validation(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	setupFounder(t, database, t.TempDir())

	for _, name := range []string{"../x", "a/b", ".trash", "Bob"} {
		if _, err := request(q, name, "long-enough"); !errors.Is(err, authutil.ErrInvalidUsername) {
			t.Errorf("request %q = %v, want ErrInvalidUsername", name, err)
		}
	}
	if _, err := request(q, "bob", "short"); !errors.Is(err, authutil.ErrPasswordTooShort) {
		t.Errorf("short password = %v, want ErrPasswordTooShort", err)
	}
}
