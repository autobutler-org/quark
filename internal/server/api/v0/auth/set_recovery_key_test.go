package v0_auth_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
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

// TestSetRecoveryKey_Rotation drives the rotation a sign-in from an updated
// client makes: refused without a session or an auth salt, all-or-nothing with
// chat keys, and afterwards the old phrase stops recovering the account.
func TestSetRecoveryKey_Rotation(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	queries := database.Queries
	const phrase = "apple-bread-cloud-delta-eagle-flame"
	createRecoverableUser(t, queries, "bob", phrase)
	bob := userByName(t, queries, "bob")
	recoveryKey := authKeyOf(9)

	const password = "original-password"
	if w := putRecoveryKey(t, database, db.User{}, map[string]string{"password": password, "recoveryKey": recoveryKey}); w.Code != http.StatusUnauthorized {
		t.Errorf("without a session = %d, want 401", w.Code)
	}
	if w := putRecoveryKey(t, database, bob, map[string]string{"password": password, "recoveryKey": recoveryKey}); w.Code != http.StatusConflict {
		t.Errorf("without an auth salt = %d %s, want 409", w.Code, w.Body)
	}

	login := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "bob", "password": "original-password", "authKey": authKeyOf(1)})
	if login.Code != http.StatusOK || decodeBody(t, login)["legacyRecovery"] != true {
		t.Fatalf("legacy login = %d %s, want 200 and legacyRecovery true", login.Code, login.Body)
	}
	if _, legacy := saltFor(t, engine, "bob"); legacy {
		t.Error("bob is upgraded, salt should say legacy false")
	}
	if w := getPath(engine, "/api/v0/auth/salt?username=bob"); decodeBody(t, w)["legacyRecovery"] != true {
		t.Errorf("salt before rotation = %s, want legacyRecovery true", w.Body)
	}

	// A session alone cannot replace the recovery credential: a wrong or
	// missing re-confirmation gets delete-account's 403 and writes nothing.
	wrong := putRecoveryKey(t, database, bob, map[string]any{"password": "not-it", "recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)})
	missing := putRecoveryKey(t, database, bob, map[string]any{"recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)})
	for name, w := range map[string]*httptest.ResponseRecorder{"wrong password": wrong, "missing password": missing} {
		if w.Code != http.StatusForbidden || decodeBody(t, w)["error"] != authutil.ErrIncorrectPassword.Error() {
			t.Errorf("%s = %d %s, want 403 incorrect password", name, w.Code, w.Body)
		}
	}
	if row := userByName(t, queries, "bob"); row.RecoveryKeyHash != "" || row.RecoveryPhraseHash != bob.RecoveryPhraseHash {
		t.Error("a refused re-confirmation changed the recovery credentials")
	}
	if _, err := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: context.Background(), Queries: queries, UserID: bob.ID}); err == nil {
		t.Error("a refused re-confirmation stored chat keys")
	}

	for name, body := range map[string]any{
		"malformed key":       map[string]string{"password": password, "recoveryKey": "not-base64"},
		"no key":              map[string]string{"password": password},
		"malformed chat keys": map[string]any{"password": password, "recoveryKey": recoveryKey, "chatKeys": chatutil.Keys{}},
	} {
		if w := putRecoveryKey(t, database, bob, body); w.Code != http.StatusBadRequest {
			t.Errorf("%s = %d %s, want 400", name, w.Code, w.Body)
		}
	}

	// A chat key write that fails inside the transaction leaves both recovery
	// credentials as they were.
	if _, err := database.Db.Exec(`CREATE TRIGGER refuse_chat_keys BEFORE INSERT ON user_chat_keys BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
		t.Fatal(err)
	}
	if w := putRecoveryKey(t, database, bob, map[string]any{"password": password, "recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)}); w.Code != http.StatusInternalServerError {
		t.Errorf("failing chat keys write = %d %s, want 500", w.Code, w.Body)
	}
	if row := userByName(t, queries, "bob"); row.RecoveryKeyHash != "" || row.RecoveryPhraseHash != bob.RecoveryPhraseHash {
		t.Error("a failed chat keys write changed the recovery credentials")
	}
	if _, err := database.Db.Exec(`DROP TRIGGER refuse_chat_keys`); err != nil {
		t.Fatal(err)
	}

	// The auth key re-confirms in the password slot too.
	if w := putRecoveryKey(t, database, bob, map[string]any{"password": authKeyOf(1), "recoveryKey": recoveryKey, "chatKeys": chatKeysOf(3)}); w.Code != http.StatusNoContent {
		t.Fatalf("rotation = %d %s, want 204", w.Code, w.Body)
	}
	if row := userByName(t, queries, "bob"); row.RecoveryPhraseHash != "" || row.RecoveryKeyHash == "" {
		t.Error("rotation should store the key and clear the phrase hash")
	}
	got, err := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: context.Background(), Queries: queries, UserID: bob.ID})
	if err != nil || !bytes.Equal(got.Keys.WrappedByPhrase, bytes.Repeat([]byte{3}, 104)) {
		t.Errorf("rotation didn't store the re-wrapped chat keys: %v", err)
	}
	if w := getPath(engine, "/api/v0/auth/salt?username=bob"); decodeBody(t, w)["legacyRecovery"] != false {
		t.Errorf("salt after rotation = %s, want legacyRecovery false", w.Body)
	}
	if w := getPath(engine, "/api/v0/auth/salt?username=nobody"); decodeBody(t, w)["legacyRecovery"] != false {
		t.Errorf("salt for an unknown username = %s, want legacyRecovery false", w.Body)
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "bob", "authKey": authKeyOf(1)}); decodeBody(t, w)["legacyRecovery"] != false {
		t.Errorf("login after rotation = %s, want legacyRecovery false", w.Body)
	}

	wrongPhrase := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "bob", "recoveryPhrase": "wrong-phrase"})
	oldPhrase := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "bob", "recoveryPhrase": phrase})
	wrongKey := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "bob", "recoveryKey": authKeyOf(8)})
	for name, w := range map[string]*httptest.ResponseRecorder{"old phrase": oldPhrase, "wrong key": wrongKey} {
		if w.Code != http.StatusBadRequest || w.Body.String() != wrongPhrase.Body.String() {
			t.Errorf("recover/keys with the %s = %d %s, want a wrong phrase's 400 %s", name, w.Code, w.Body, wrongPhrase.Body)
		}
	}
	if w := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "bob", "recoveryKey": recoveryKey}); w.Code != http.StatusOK {
		t.Errorf("recover/keys with the key = %d %s, want 200", w.Code, w.Body)
	}
	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryPhrase": phrase, "newAuthKey": authKeyOf(2)}); w.Code != http.StatusBadRequest {
		t.Errorf("recover with the old phrase = %d, want 400", w.Code)
	}
	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryKey": recoveryKey, "newAuthKey": authKeyOf(2)}); w.Code != http.StatusOK {
		t.Fatalf("recover with the key = %d %s, want 200", w.Code, w.Body)
	}
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "bob", "authKey": authKeyOf(2)}); w.Code != http.StatusOK {
		t.Errorf("login with the recovered auth key = %d, want 200", w.Code)
	}
}

// TestRecover_LegacyPhraseGetsRecoveryKey recovers an account that never
// rotated with its raw phrase and hands it a recovery key in the same request.
func TestRecover_LegacyPhraseGetsRecoveryKey(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	const phrase = "apple-bread-cloud-delta-eagle-flame"
	createRecoverableUser(t, database.Queries, "bob", phrase)
	recoveryKey := authKeyOf(9)

	for name, body := range map[string]map[string]string{
		"both secrets":          {"username": "bob", "recoveryPhrase": phrase, "recoveryKey": recoveryKey, "newAuthKey": authKeyOf(2)},
		"neither secret":        {"username": "bob", "newAuthKey": authKeyOf(2)},
		"malformed key":         {"username": "bob", "recoveryKey": "not-base64", "newAuthKey": authKeyOf(2)},
		"malformed new key":     {"username": "bob", "recoveryPhrase": phrase, "newAuthKey": authKeyOf(2), "newRecoveryKey": "not-base64"},
		"new key with password": {"username": "bob", "recoveryPhrase": phrase, "newPassword": "brand-new-password", "newRecoveryKey": recoveryKey},
	} {
		if w := postJSON(engine, "/api/v0/auth/recover", body); w.Code != http.StatusBadRequest {
			t.Errorf("recover %s = %d %s, want 400", name, w.Code, w.Body)
		}
	}
	if row := userByName(t, database.Queries, "bob"); row.RecoveryKeyHash != "" {
		t.Fatal("a refused recovery stored a recovery key")
	}

	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryPhrase": phrase, "newAuthKey": authKeyOf(2), "newRecoveryKey": recoveryKey}); w.Code != http.StatusOK {
		t.Fatalf("legacy recover with a new recovery key = %d %s, want 200", w.Code, w.Body)
	}
	if w := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "bob", "recoveryPhrase": phrase}); w.Code != http.StatusBadRequest {
		t.Errorf("old phrase after rotation = %d, want 400", w.Code)
	}
	if w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryKey": recoveryKey, "newAuthKey": authKeyOf(3)}); w.Code != http.StatusOK {
		t.Errorf("recover with the new recovery key = %d %s, want 200", w.Code, w.Body)
	}
}

// TestRequestAccount_RecoveryKey asks for an account with a recovery key: no
// phrase comes back, a password beside the key is refused, and the key
// recovers the account once it is approved.
func TestRequestAccount_RecoveryKey(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	recoveryKey := authKeyOf(9)

	if w := postJSON(engine, "/api/v0/auth/request-account", map[string]string{"username": "asker", "password": "long-enough", "recoveryKey": recoveryKey}); w.Code != http.StatusBadRequest {
		t.Errorf("recovery key with a password = %d %s, want 400", w.Code, w.Body)
	}
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
