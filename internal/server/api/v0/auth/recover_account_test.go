package v0_auth_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestRecoverAccount_NamedAccount drives POST /auth/recover against a Quark
// with two accounts. The recovery key is checked against the account the
// request names, and an unknown username is indistinguishable from a wrong
// key.
func TestRecoverAccount_NamedAccount(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	ctx := context.Background()
	createRecoverableUser(t, database.Queries, "bob", "bob-phrase")

	recoverAs := func(username, phrase string) *httptest.ResponseRecorder {
		return postJSON(engine, "/api/v0/auth/recover", map[string]string{
			"username":    username,
			"recoveryKey": dbtest.AuthKey(phrase),
			"newAuthKey":  dbtest.AuthKey("brand-new-password"),
		})
	}

	wrongUser := recoverAs("admin", "bob-phrase")
	if wrongUser.Code != http.StatusBadRequest {
		t.Errorf("admin with bob's key = %d, want 400: %s", wrongUser.Code, wrongUser.Body.String())
	}
	unknownUser := recoverAs("nobody", "bob-phrase")
	if unknownUser.Code != http.StatusBadRequest {
		t.Errorf("unknown user = %d, want 400: %s", unknownUser.Code, unknownUser.Body.String())
	}
	if unknownUser.Body.String() != wrongUser.Body.String() {
		t.Errorf("unknown user body %q differs from wrong key body %q", unknownUser.Body.String(), wrongUser.Body.String())
	}

	rightUser := recoverAs("bob", "bob-phrase")
	if rightUser.Code != http.StatusOK {
		t.Fatalf("bob with bob's key = %d, want 200: %s", rightUser.Code, rightUser.Body.String())
	}
	if _, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "bob", AuthKey: dbtest.AuthKey("brand-new-password")}); err != nil {
		t.Errorf("bob should log in with the new password: %v", err)
	}
	if _, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "admin", AuthKey: dbtest.AuthKey("admin-password")}); err != nil {
		t.Errorf("admin's password must be untouched: %v", err)
	}
}

// createRecoverableUser adds an active account that signs in with the auth key
// of "original-password" and recovers with the recovery key of phrase.
func createRecoverableUser(t *testing.T, queries *db.Queries, username, phrase string) {
	t.Helper()
	keyHash, err := authutil.HashPassword(dbtest.AuthKey("original-password"))
	if err != nil {
		t.Fatal(err)
	}
	recoveryHash, err := authutil.HashPassword(dbtest.AuthKey(phrase))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := queries.CreateUser(context.Background(), db.CreateUserParams{
		Username:        username,
		AuthKeyHash:     keyHash,
		AuthSalt:        "AAAAAAAAAAAAAAAAAAAAAA==",
		RecoveryKeyHash: recoveryHash,
	}); err != nil {
		t.Fatal(err)
	}
}
