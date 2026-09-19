package v0_auth_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestLoginUser_FirstLoginPhrase checks POST /auth/login returns
// recoveryPhrase on an admin-created account's first sign-in only, and never
// for the founding admin.
func TestLoginUser_FirstLoginPhrase(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	filesDir := t.TempDir()
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: filesDir, Username: "admin", Password: "admin-password"}); err != nil {
		t.Fatal(err)
	}
	if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, Username: "bob", Password: "initial-password", FilesDir: filesDir}); err != nil {
		t.Fatal(err)
	}
	engine := newPublicAuthEngine(t, database)
	login := func(username, password string) map[string]any {
		t.Helper()
		w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": username, "password": password})
		if w.Code != http.StatusOK {
			t.Fatalf("login %s = %d: %s", username, w.Code, w.Body.String())
		}
		return decodeBody(t, w)
	}

	first := login("bob", "initial-password")
	if phrase, _ := first["recoveryPhrase"].(string); phrase == "" || first["token"] == "" {
		t.Errorf("first login body = %v, want a token and a recovery phrase", first)
	}
	if second := login("bob", "initial-password"); second["recoveryPhrase"] != nil {
		t.Errorf("second login body = %v, want no recovery phrase", second)
	}
	if founder := login("admin", "admin-password"); founder["recoveryPhrase"] != nil || len(founder) != 1 {
		t.Errorf("founder login body = %v, want only a token", founder)
	}
}
