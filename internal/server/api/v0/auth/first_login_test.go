package v0_auth_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// TestLoginUser_NoPhraseFromTheQuark checks POST /auth/login never hands out
// a recovery phrase (#2430): an admin-created account's sign-ins say
// legacyRecovery instead, so the app gives it a recovery key, and the body is
// only the token and that flag.
func TestLoginUser_NoPhraseFromTheQuark(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	files := vfs.NewMemVFS("files")
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, Files: files, Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), RecoveryKey: dbtest.AuthKey("admin-phrase"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, Username: "bob", AuthKey: dbtest.AuthKey("initial-password"), SaltSecret: dbtest.SaltSecret, Files: files}); err != nil {
		t.Fatal(err)
	}
	engine := newPublicAuthEngine(t, database)
	login := func(username, password string) map[string]any {
		t.Helper()
		w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": username, "authKey": dbtest.AuthKey(password)})
		if w.Code != http.StatusOK {
			t.Fatalf("login %s = %d: %s", username, w.Code, w.Body.String())
		}
		return decodeBody(t, w)
	}

	for range 2 {
		if bob := login("bob", "initial-password"); len(bob) != 2 || bob["token"] == "" || bob["legacyRecovery"] != true {
			t.Errorf("bob's login body = %v, want only a token and legacyRecovery true", bob)
		}
	}
	if founder := login("admin", "admin-password"); len(founder) != 2 || founder["legacyRecovery"] != false {
		t.Errorf("founder login body = %v, want only a token and legacyRecovery false", founder)
	}
}
