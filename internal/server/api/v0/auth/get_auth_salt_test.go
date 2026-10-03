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
	"github.com/gin-gonic/gin"
)

// authKeyOf returns a well-formed auth key: the base64 of 32 bytes of fill.
func authKeyOf(fill byte) string {
	return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{fill}, 32))
}

// newAuthKeyEngine is a Quark whose founding admin "admin" signs in with the
// raw password "admin-password", and whose salt secret lives in a temporary
// settings file.
func newAuthKeyEngine(t *testing.T) (*gin.Engine, *db.DatabaseSqlc) {
	t.Helper()
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	t.Cleanup(func() { settingsutil.ResetForTesting("") })
	database := dbtest.NewDB(t)
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", Password: "admin-password"}); err != nil {
		t.Fatal(err)
	}
	return newPublicAuthEngine(t, database), database
}

// saltFor reads GET /auth/salt for username, which must answer 200.
func saltFor(t *testing.T, engine *gin.Engine, username string) (salt string, legacy bool) {
	t.Helper()
	w := getPath(engine, "/api/v0/auth/salt?username="+username)
	if w.Code != http.StatusOK {
		t.Fatalf("salt for %q = %d: %s", username, w.Code, w.Body.String())
	}
	body := decodeBody(t, w)
	salt, _ = body["salt"].(string)
	legacy, isBool := body["legacy"].(bool)
	if raw, err := base64.StdEncoding.DecodeString(salt); err != nil || len(raw) != 16 || !isBool {
		t.Fatalf("salt for %q = %s, want a base64 16-byte salt and a bool legacy", username, w.Body.String())
	}
	return salt, legacy
}

// TestGetAuthSalt drives GET /auth/salt for an unknown, a legacy and an
// upgraded account. An unknown username is answered like a known one, the
// salt is the same on every call, and only the legacy account is flagged.
func TestGetAuthSalt(t *testing.T) {
	engine, _ := newAuthKeyEngine(t)

	for _, path := range []string{"/api/v0/auth/salt", "/api/v0/auth/salt?username="} {
		if w := getPath(engine, path); w.Code != http.StatusBadRequest {
			t.Errorf("GET %s = %d, want 400", path, w.Code)
		}
	}

	unknownSalt, unknownLegacy := saltFor(t, engine, "nobody")
	legacySalt, legacyLegacy := saltFor(t, engine, "admin")
	if unknownLegacy || !legacyLegacy {
		t.Errorf("legacy flags: unknown %v, legacy account %v; want false, true", unknownLegacy, legacyLegacy)
	}
	if again, _ := saltFor(t, engine, "nobody"); again != unknownSalt {
		t.Errorf("unknown salt changed between calls: %q then %q", unknownSalt, again)
	}
	if again, _ := saltFor(t, engine, "admin"); again != legacySalt {
		t.Errorf("legacy salt changed between calls: %q then %q", legacySalt, again)
	}

	upgrade := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "password": "admin-password", "authKey": authKeyOf(1)})
	if upgrade.Code != http.StatusOK {
		t.Fatalf("upgrade = %d: %s", upgrade.Code, upgrade.Body.String())
	}
	if salt, legacy := saltFor(t, engine, "admin"); legacy || salt != legacySalt {
		t.Errorf("upgraded salt = %q legacy %v, want %q and false", salt, legacy, legacySalt)
	}
}

// TestLoginUser_Shapes drives POST /auth/login through its three bodies. A
// key is a plain 401 before the upgrade, the upgrade keeps the legacy body
// working, and a malformed key or a body with neither credential is a 400.
func TestLoginUser_Shapes(t *testing.T) {
	engine, _ := newAuthKeyEngine(t)
	key := authKeyOf(1)
	post := func(body map[string]string) int {
		return postJSON(engine, "/api/v0/auth/login", body).Code
	}

	early := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "authKey": key})
	wrong := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "password": "not-it"})
	if early.Code != http.StatusUnauthorized || early.Body.String() != wrong.Body.String() {
		t.Errorf("auth key before upgrade = %d %s, want the wrong password's 401 %s", early.Code, early.Body.String(), wrong.Body.String())
	}
	for name, body := range map[string]map[string]string{
		"malformed key":            {"username": "admin", "authKey": "not-base64"},
		"short key":                {"username": "admin", "authKey": base64.StdEncoding.EncodeToString([]byte("short"))},
		"malformed key in upgrade": {"username": "admin", "password": "admin-password", "authKey": "not-base64"},
		"no credential":            {"username": "admin"},
		"no username":              {"password": "admin-password"},
	} {
		if code := post(body); code != http.StatusBadRequest {
			t.Errorf("%s = %d, want 400", name, code)
		}
	}
	if code := post(map[string]string{"username": "admin", "password": "not-it", "authKey": key}); code != http.StatusUnauthorized {
		t.Errorf("upgrade with a wrong password = %d, want 401", code)
	}

	upgrade := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "password": "admin-password", "authKey": key})
	if upgrade.Code != http.StatusOK || decodeBody(t, upgrade)["token"] == "" {
		t.Fatalf("upgrade = %d: %s", upgrade.Code, upgrade.Body.String())
	}
	withKey := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "authKey": key})
	if token, _ := decodeBody(t, withKey)["token"].(string); withKey.Code != http.StatusOK || token == "" {
		t.Errorf("auth key login = %d: %s", withKey.Code, withKey.Body.String())
	}
	if code := post(map[string]string{"username": "admin", "password": "admin-password"}); code != http.StatusOK {
		t.Errorf("legacy login after upgrade = %d, want 200", code)
	}
	if code := post(map[string]string{"username": "admin", "authKey": authKeyOf(2)}); code != http.StatusUnauthorized {
		t.Errorf("wrong auth key = %d, want 401", code)
	}
}

// TestRequestAndRecover_AuthKey checks the account-making and recovery bodies
// take an auth key in place of the password, and refuse both or neither.
func TestRequestAndRecover_AuthKey(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	key, newKey := authKeyOf(1), authKeyOf(2)

	for name, body := range map[string]map[string]string{
		"both":      {"username": "asker", "password": "long-enough", "authKey": key},
		"neither":   {"username": "asker"},
		"malformed": {"username": "asker", "authKey": "not-base64"},
	} {
		if w := postJSON(engine, "/api/v0/auth/request-account", body); w.Code != http.StatusBadRequest {
			t.Errorf("request-account %s = %d, want 400: %s", name, w.Code, w.Body.String())
		}
	}
	offered, _ := saltFor(t, engine, "asker")
	requested := postJSON(engine, "/api/v0/auth/request-account", map[string]string{"username": "asker", "authKey": key})
	if requested.Code != http.StatusCreated {
		t.Fatalf("request-account = %d: %s", requested.Code, requested.Body.String())
	}
	phrase, _ := decodeBody(t, requested)["recoveryPhrase"].(string)
	setUserStatus(t, database.Queries, "asker", authutil.StatusPending, authutil.StatusActive)
	if salt, legacy := saltFor(t, engine, "asker"); legacy || salt != offered {
		t.Errorf("salt after request = %q legacy %v, want %q and false", salt, legacy, offered)
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "asker", "authKey": key}); w.Code != http.StatusOK {
		t.Fatalf("login with the requested key = %d: %s", w.Code, w.Body.String())
	}

	for name, body := range map[string]map[string]string{
		"both":      {"username": "asker", "recoveryPhrase": phrase, "newPassword": "brand-new-password", "newAuthKey": newKey},
		"neither":   {"username": "asker", "recoveryPhrase": phrase},
		"malformed": {"username": "asker", "recoveryPhrase": phrase, "newAuthKey": "not-base64"},
	} {
		if w := postJSON(engine, "/api/v0/auth/recover", body); w.Code != http.StatusBadRequest {
			t.Errorf("recover %s = %d, want 400: %s", name, w.Code, w.Body.String())
		}
	}
	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "asker", "recoveryPhrase": phrase, "newAuthKey": newKey}); w.Code != http.StatusOK {
		t.Fatalf("recover with an auth key = %d: %s", w.Code, w.Body.String())
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "asker", "authKey": key}); w.Code != http.StatusUnauthorized {
		t.Errorf("old key after recovery = %d, want 401", w.Code)
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "asker", "authKey": newKey}); w.Code != http.StatusOK {
		t.Errorf("new key after recovery = %d, want 200", w.Code)
	}

	// A legacy recovery ends the key: it was derived from the old password.
	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "asker", "recoveryPhrase": phrase, "newPassword": "brand-new-password"}); w.Code != http.StatusOK {
		t.Fatalf("recover with a password = %d: %s", w.Code, w.Body.String())
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "asker", "authKey": newKey}); w.Code != http.StatusUnauthorized {
		t.Errorf("key after a password recovery = %d, want 401", w.Code)
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "asker", "password": "brand-new-password"}); w.Code != http.StatusOK {
		t.Errorf("new password after recovery = %d, want 200", w.Code)
	}
}
