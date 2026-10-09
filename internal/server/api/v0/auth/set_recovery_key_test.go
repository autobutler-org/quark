package v0_auth_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// putRecoveryKey sends PUT /auth/recovery-key as the caller, the way
// requireAuth leaves a signed-in one; a zero user sends it with no caller.
func putRecoveryKey(t *testing.T, database *db.DatabaseSqlc, caller db.User, body any) *httptest.ResponseRecorder {
	t.Helper()
	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		if caller.ID != 0 {
			c = ctxutil.With(c, "userID", caller.ID)
			c = ctxutil.With(c, "username", caller.Username)
		}
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_auth.NewRouter())
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPut, "/api/v0/auth/recovery-key", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

func chatKeysOf(fill byte) chatutil.Keys {
	b := func(n int) []byte { return bytes.Repeat([]byte{fill}, n) }
	return chatutil.Keys{
		BoxPublicKey: b(32), SignPublicKey: b(32),
		WrappedByPassword: b(104), SaltPw: b(16),
		WrappedByPhrase: b(104), SaltRp: b(16),
		KdfParams: json.RawMessage(`{"alg":"argon2id13","opsLimit":3,"memLimit":67108864}`),
	}
}

func userByName(t *testing.T, queries *db.Queries, username string) db.User {
	t.Helper()
	user, err := queries.GetUserByUsername(context.Background(), username)
	if err != nil {
		t.Fatal(err)
	}
	return user
}

// TestSetRecoveryKey_Rotation drives what the app does at a sign-in that
// reads legacyRecovery, such as an admin-created account's first: refused
// without a session or the caller's auth key, all-or-nothing with chat keys,
// and afterwards the key recovers the account (#2430).
func TestSetRecoveryKey_Rotation(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	queries := database.Queries
	key := dbtest.AuthKey("original-password")
	if _, err := authutil.CreateUser(context.Background(), authutil.CreateUserParams{Database: database, Username: "bob", AuthKey: key, SaltSecret: dbtest.SaltSecret, Files: vfs.NewMemVFS("files")}); err != nil {
		t.Fatal(err)
	}
	bob := userByName(t, queries, "bob")
	recoveryKey := authKeyOf(9)

	if w := putRecoveryKey(t, database, db.User{}, map[string]string{"password": key, "recoveryKey": recoveryKey}); w.Code != http.StatusUnauthorized {
		t.Errorf("without a session = %d, want 401", w.Code)
	}
	login := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "bob", "authKey": key})
	if login.Code != http.StatusOK || decodeBody(t, login)["legacyRecovery"] != true {
		t.Fatalf("first login = %d %s, want 200 and legacyRecovery true", login.Code, login.Body)
	}
	if _, legacy, legacyRecovery := saltFor(t, engine, "bob"); legacy || !legacyRecovery {
		t.Errorf("salt before rotation: legacy %v legacyRecovery %v, want false, true", legacy, legacyRecovery)
	}

	// A session alone cannot replace the recovery credential: a wrong or
	// missing re-confirmation gets delete-account's 403, a raw password the
	// update-the-app 426, and neither writes anything.
	wrong := putRecoveryKey(t, database, bob, map[string]any{"password": authKeyOf(2), "recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)})
	missing := putRecoveryKey(t, database, bob, map[string]any{"recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)})
	for name, w := range map[string]*httptest.ResponseRecorder{"wrong key": wrong, "missing key": missing} {
		if w.Code != http.StatusForbidden || decodeBody(t, w)["error"] != authutil.ErrIncorrectPassword.Error() {
			t.Errorf("%s = %d %s, want 403 incorrect password", name, w.Code, w.Body)
		}
	}
	raw := putRecoveryKey(t, database, bob, map[string]any{"password": "original-password", "recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)})
	if raw.Code != http.StatusUpgradeRequired || decodeBody(t, raw)["error"] != authutil.ErrAppTooOld.Error() {
		t.Errorf("raw password = %d %s, want 426 with the update-the-app copy", raw.Code, raw.Body)
	}
	if row := userByName(t, queries, "bob"); row.RecoveryKeyHash != "" {
		t.Error("a refused re-confirmation stored a recovery key")
	}
	if _, err := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: context.Background(), Queries: queries, UserID: bob.ID}); err == nil {
		t.Error("a refused re-confirmation stored chat keys")
	}

	for name, body := range map[string]any{
		"malformed key":       map[string]string{"password": key, "recoveryKey": "not-base64"},
		"no key":              map[string]string{"password": key},
		"malformed chat keys": map[string]any{"password": key, "recoveryKey": recoveryKey, "chatKeys": chatutil.Keys{}},
	} {
		if w := putRecoveryKey(t, database, bob, body); w.Code != http.StatusBadRequest {
			t.Errorf("%s = %d %s, want 400", name, w.Code, w.Body)
		}
	}

	// A chat key write that fails inside the transaction leaves the recovery
	// credential as it was.
	if _, err := database.Db.Exec(`CREATE TRIGGER refuse_chat_keys BEFORE INSERT ON user_chat_keys BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
		t.Fatal(err)
	}
	if w := putRecoveryKey(t, database, bob, map[string]any{"password": key, "recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)}); w.Code != http.StatusInternalServerError {
		t.Errorf("failing chat keys write = %d %s, want 500", w.Code, w.Body)
	}
	if row := userByName(t, queries, "bob"); row.RecoveryKeyHash != "" {
		t.Error("a failed chat keys write stored a recovery key")
	}
	if _, err := database.Db.Exec(`DROP TRIGGER refuse_chat_keys`); err != nil {
		t.Fatal(err)
	}

	if w := putRecoveryKey(t, database, bob, map[string]any{"password": key, "recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)}); w.Code != http.StatusNoContent {
		t.Fatalf("rotation = %d %s, want 204", w.Code, w.Body)
	}
	if row := userByName(t, queries, "bob"); row.RecoveryKeyHash == "" {
		t.Error("rotation should store the key")
	}
	got, err := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: context.Background(), Queries: queries, UserID: bob.ID})
	if err != nil || !bytes.Equal(got.Keys.WrappedByPhrase, bytes.Repeat([]byte{3}, 104)) {
		t.Errorf("rotation didn't store the re-wrapped chat keys: %v", err)
	}
	if _, _, legacyRecovery := saltFor(t, engine, "bob"); legacyRecovery {
		t.Error("salt after rotation should read legacyRecovery false")
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "bob", "authKey": key}); decodeBody(t, w)["legacyRecovery"] != false {
		t.Errorf("login after rotation = %s, want legacyRecovery false", w.Body)
	}

	wrongKey := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "bob", "recoveryKey": authKeyOf(8)})
	unknown := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "nobody", "recoveryKey": recoveryKey})
	if wrongKey.Code != http.StatusBadRequest || unknown.Body.String() != wrongKey.Body.String() {
		t.Errorf("recover/keys with a wrong key = %d %s and an unknown user %s, want the same 400", wrongKey.Code, wrongKey.Body, unknown.Body)
	}
	if w := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "bob", "recoveryKey": recoveryKey}); w.Code != http.StatusOK {
		t.Errorf("recover/keys with the key = %d %s, want 200", w.Code, w.Body)
	}
	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryKey": recoveryKey, "newAuthKey": authKeyOf(2)}); w.Code != http.StatusOK {
		t.Fatalf("recover with the key = %d %s, want 200", w.Code, w.Body)
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "bob", "authKey": authKeyOf(2)}); w.Code != http.StatusOK {
		t.Errorf("login with the recovered auth key = %d, want 200", w.Code)
	}
}

// TestRequestAccount_RecoveryKey asks for an account with a recovery key: no
// phrase comes back, a malformed key is refused, and the key recovers the
// account once it is approved.
func TestRequestAccount_RecoveryKey(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	recoveryKey := authKeyOf(9)

	if w := postJSON(engine, "/api/v0/auth/request-account", map[string]string{"username": "asker", "authKey": authKeyOf(1), "recoveryKey": "not-base64"}); w.Code != http.StatusBadRequest {
		t.Errorf("malformed recovery key = %d %s, want 400", w.Code, w.Body)
	}
	requested := postJSON(engine, "/api/v0/auth/request-account", map[string]string{"username": "asker", "authKey": authKeyOf(1), "recoveryKey": recoveryKey})
	if requested.Code != http.StatusCreated {
		t.Fatalf("request-account = %d %s", requested.Code, requested.Body)
	}
	if _, has := decodeBody(t, requested)["recoveryPhrase"]; has {
		t.Errorf("request with a recovery key returned a phrase: %s", requested.Body)
	}
	setUserStatus(t, database.Queries, "asker", authutil.StatusPending, authutil.StatusActive)
	if w := getPath(engine, "/api/v0/auth/salt?username=asker"); decodeBody(t, w)["legacyRecovery"] != false {
		t.Errorf("salt = %s, want legacyRecovery false", w.Body)
	}
	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "asker", "recoveryKey": recoveryKey, "newAuthKey": authKeyOf(2)}); w.Code != http.StatusOK {
		t.Errorf("recover with the requested key = %d %s, want 200", w.Code, w.Body)
	}
}
