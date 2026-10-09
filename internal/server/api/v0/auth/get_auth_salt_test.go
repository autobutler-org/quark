package v0_auth_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"net/http"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// authKeyOf returns a well-formed auth key: the base64 of 32 bytes of fill.
func authKeyOf(fill byte) string {
	return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{fill}, 32))
}

// newAuthKeyEngine is a Quark whose founding admin "admin" signs in with the
// auth key of "admin-password", beside "old", an account from before auth
// keys with the hashes of the password "old-password" and the phrase
// "old-phrase", and whose salt secret lives in a temporary settings file.
func newAuthKeyEngine(t *testing.T) (*gin.Engine, *db.DatabaseSqlc) {
	t.Helper()
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	t.Cleanup(func() { settingsutil.ResetForTesting("") })
	database := dbtest.NewDB(t)
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, Files: vfs.NewMemVFS("files"), Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{Username: "old", PasswordHash: dbtest.BcryptHash(t, "old-password"), RecoveryPhraseHash: dbtest.BcryptHash(t, "old-phrase")}); err != nil {
		t.Fatal(err)
	}
	return newPublicAuthEngine(t, database), database
}

// saltFor reads GET /auth/salt for username, which must answer 200.
func saltFor(t *testing.T, engine *gin.Engine, username string) (salt string, legacy, legacyRecovery bool) {
	t.Helper()
	w := getPath(engine, "/api/v0/auth/salt?username="+username)
	if w.Code != http.StatusOK {
		t.Fatalf("salt for %q = %d: %s", username, w.Code, w.Body.String())
	}
	body := decodeBody(t, w)
	salt, _ = body["salt"].(string)
	legacy, isBool := body["legacy"].(bool)
	legacyRecovery, isBoolToo := body["legacyRecovery"].(bool)
	if raw, err := base64.StdEncoding.DecodeString(salt); err != nil || len(raw) != 16 || !isBool || !isBoolToo {
		t.Fatalf("salt for %q = %s, want a base64 16-byte salt and two bools", username, w.Body.String())
	}
	return salt, legacy, legacyRecovery
}

// TestGetAuthSalt drives GET /auth/salt for an unknown account, one from
// before auth keys, and one that has moved to them. An unknown username is
// answered like a moved one, the salt is the same on every call, and only the
// old account reads as legacy (#2430).
func TestGetAuthSalt(t *testing.T) {
	engine, _ := newAuthKeyEngine(t)

	for _, path := range []string{"/api/v0/auth/salt", "/api/v0/auth/salt?username="} {
		if w := getPath(engine, path); w.Code != http.StatusBadRequest {
			t.Errorf("GET %s = %d, want 400", path, w.Code)
		}
	}

	for _, tc := range []struct {
		username               string
		legacy, legacyRecovery bool
	}{
		{"nobody", false, false},
		{"old", true, true},
		{"admin", false, true},
	} {
		salt, legacy, legacyRecovery := saltFor(t, engine, tc.username)
		if legacy != tc.legacy || legacyRecovery != tc.legacyRecovery {
			t.Errorf("%s: legacy %v legacyRecovery %v, want %v %v", tc.username, legacy, legacyRecovery, tc.legacy, tc.legacyRecovery)
		}
		if again, _, _ := saltFor(t, engine, tc.username); again != salt {
			t.Errorf("%s: salt changed between calls: %q then %q", tc.username, salt, again)
		}
	}
}

// TestLoginUser_AuthKey drives POST /auth/login with {username, authKey}: the
// right key signs in, a wrong one or an account with no key is a 401, and a
// missing or malformed key is a 400.
func TestLoginUser_AuthKey(t *testing.T) {
	engine, _ := newAuthKeyEngine(t)
	key := dbtest.AuthKey("admin-password")
	post := func(body map[string]string) int {
		return postJSON(engine, "/api/v0/auth/login", body).Code
	}

	withKey := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "authKey": key})
	if token, _ := decodeBody(t, withKey)["token"].(string); withKey.Code != http.StatusOK || token == "" {
		t.Errorf("auth key login = %d: %s", withKey.Code, withKey.Body.String())
	}
	for name, body := range map[string]map[string]string{
		"malformed key": {"username": "admin", "authKey": "not-base64"},
		"short key":     {"username": "admin", "authKey": base64.StdEncoding.EncodeToString([]byte("short"))},
		"no credential": {"username": "admin"},
		"no username":   {"authKey": key},
	} {
		if code := post(body); code != http.StatusBadRequest {
			t.Errorf("%s = %d, want 400", name, code)
		}
	}
	wrong := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "authKey": authKeyOf(2)})
	old := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "old", "authKey": key})
	if wrong.Code != http.StatusUnauthorized || old.Code != http.StatusUnauthorized || old.Body.String() != wrong.Body.String() {
		t.Errorf("wrong key = %d %s and an account with no key = %d %s, want the same 401", wrong.Code, wrong.Body.String(), old.Code, old.Body.String())
	}
}

// TestRequestAndRecover_AuthKey checks the account-making and recovery bodies
// take keys and refuse malformed ones.
func TestRequestAndRecover_AuthKey(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	key, newKey, recoveryKey := authKeyOf(1), authKeyOf(2), authKeyOf(9)

	for name, body := range map[string]map[string]string{
		"neither":            {"username": "asker"},
		"malformed":          {"username": "asker", "authKey": "not-base64"},
		"malformed recovery": {"username": "asker", "authKey": key, "recoveryKey": "not-base64"},
	} {
		if w := postJSON(engine, "/api/v0/auth/request-account", body); w.Code != http.StatusBadRequest {
			t.Errorf("request-account %s = %d, want 400: %s", name, w.Code, w.Body.String())
		}
	}
	offered, _, _ := saltFor(t, engine, "asker")
	requested := postJSON(engine, "/api/v0/auth/request-account", map[string]string{"username": "asker", "authKey": key, "recoveryKey": recoveryKey})
	if requested.Code != http.StatusCreated || requested.Body.String() != "{}" {
		t.Fatalf("request-account = %d %s, want 201 and an empty object", requested.Code, requested.Body.String())
	}
	setUserStatus(t, database.Queries, "asker", authutil.StatusPending, authutil.StatusActive)
	if salt, legacy, legacyRecovery := saltFor(t, engine, "asker"); legacy || legacyRecovery || salt != offered {
		t.Errorf("salt after request = %q legacy %v legacyRecovery %v, want %q and false, false", salt, legacy, legacyRecovery, offered)
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "asker", "authKey": key}); w.Code != http.StatusOK {
		t.Fatalf("login with the requested key = %d: %s", w.Code, w.Body.String())
	}

	for name, body := range map[string]map[string]string{
		"no new key":        {"username": "asker", "recoveryKey": recoveryKey},
		"malformed new key": {"username": "asker", "recoveryKey": recoveryKey, "newAuthKey": "not-base64"},
		"no recovery key":   {"username": "asker", "newAuthKey": newKey},
		"wrong recovery":    {"username": "asker", "recoveryKey": authKeyOf(8), "newAuthKey": newKey},
	} {
		if w := postJSON(engine, "/api/v0/auth/recover", body); w.Code != http.StatusBadRequest {
			t.Errorf("recover %s = %d, want 400: %s", name, w.Code, w.Body.String())
		}
	}
	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "asker", "recoveryKey": recoveryKey, "newAuthKey": newKey}); w.Code != http.StatusOK {
		t.Fatalf("recover = %d: %s", w.Code, w.Body.String())
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "asker", "authKey": key}); w.Code != http.StatusUnauthorized {
		t.Errorf("old key after recovery = %d, want 401", w.Code)
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "asker", "authKey": newKey}); w.Code != http.StatusOK {
		t.Errorf("new key after recovery = %d, want 200", w.Code)
	}
}
