package v0_auth_test

import (
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestLoginUser_Upgrade moves "old" to an auth key through POST /auth/login
// (#2430). {password, authKey} signs in once and clears the password hash;
// after that the password beside a wrong key is a 401 and the password alone
// a 426, while the key signs in.
func TestLoginUser_Upgrade(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	salt, _, _ := saltFor(t, engine, "old")
	key := dbtest.AuthKey("old-password")
	login := func(body map[string]string) int {
		return postJSON(engine, "/api/v0/auth/login", body).Code
	}

	if code := login(map[string]string{"username": "old", "password": "wrong-password", "authKey": key}); code != http.StatusUnauthorized {
		t.Errorf("wrong password beside a key = %d, want 401", code)
	}
	w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "old", "password": "old-password", "authKey": key})
	if token, _ := decodeBody(t, w)["token"].(string); w.Code != http.StatusOK || token == "" {
		t.Fatalf("upgrade = %d %s, want 200 and a token", w.Code, w.Body)
	}
	user := userByName(t, database.Queries, "old")
	if user.PasswordHash != "" || user.AuthSalt != salt || !authutil.CheckPassword(key, user.AuthKeyHash) {
		t.Errorf("after the upgrade password hash %q salt %q, want cleared and %q, and the key stored", user.PasswordHash, user.AuthSalt, salt)
	}
	if _, legacy, _ := saltFor(t, engine, "old"); legacy {
		t.Error("the upgraded account still reads as legacy")
	}
	if code := login(map[string]string{"username": "old", "password": "old-password", "authKey": authKeyOf(7)}); code != http.StatusUnauthorized {
		t.Errorf("the password beside a wrong key after the upgrade = %d, want 401", code)
	}
	if code := login(map[string]string{"username": "old", "password": "old-password"}); code != http.StatusUpgradeRequired {
		t.Errorf("the password alone after the upgrade = %d, want 426", code)
	}
	if code := login(map[string]string{"username": "old", "authKey": key}); code != http.StatusOK {
		t.Errorf("the key after the upgrade = %d, want 200", code)
	}
}

// TestLoginUser_UpgradeWriteFails answers 500 when the upgrade's write does
// not land, and the account stays on its password.
func TestLoginUser_UpgradeWriteFails(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	if _, err := database.Db.Exec(`CREATE TRIGGER refuse_upgrade BEFORE UPDATE OF auth_key_hash ON users
		BEGIN SELECT RAISE(ABORT, 'disk full'); END`); err != nil {
		t.Fatal(err)
	}
	w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "old", "password": "old-password", "authKey": dbtest.AuthKey("old-password")})
	if _, hasToken := decodeBody(t, w)["token"]; w.Code != http.StatusInternalServerError || hasToken {
		t.Errorf("failed upgrade = %d %s, want 500 and no token", w.Code, w.Body)
	}
	if user := userByName(t, database.Queries, "old"); user.AuthKeyHash != "" || user.PasswordHash == "" {
		t.Error("a failed upgrade changed the account")
	}
}

// TestRecover_LegacyPhrase drives the one phrase recovery of "old" (#2430):
// recover/keys takes its raw phrase while it has no recovery key, recover
// takes it beside both new keys and clears both raw-secret hashes, and after
// that neither endpoint takes the phrase.
func TestRecover_LegacyPhrase(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	newKey, newRecoveryKey := authKeyOf(5), authKeyOf(6)
	phraseKeys := func(phrase string) int {
		return postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "old", "recoveryPhrase": phrase}).Code
	}

	// old has no chat keys, so the right phrase is a 404 and a wrong one a 400.
	if code := phraseKeys("old-phrase"); code != http.StatusNotFound {
		t.Errorf("recover/keys with the legacy phrase = %d, want 404 for no chat keys", code)
	}
	if code := phraseKeys("other-phrase"); code != http.StatusBadRequest {
		t.Errorf("recover/keys with a wrong phrase = %d, want 400", code)
	}

	w := postJSON(engine, "/api/v0/auth/recover", map[string]string{
		"username": "old", "recoveryPhrase": "old-phrase", "newAuthKey": newKey, "newRecoveryKey": newRecoveryKey,
	})
	if token, _ := decodeBody(t, w)["token"].(string); w.Code != http.StatusOK || token == "" {
		t.Fatalf("legacy recovery = %d %s, want 200 and a token", w.Code, w.Body)
	}
	user := userByName(t, database.Queries, "old")
	if user.PasswordHash != "" || user.RecoveryPhraseHash != "" {
		t.Errorf("kept password hash %q phrase hash %q, want both cleared", user.PasswordHash, user.RecoveryPhraseHash)
	}
	if code := phraseKeys("old-phrase"); code != http.StatusBadRequest {
		t.Errorf("recover/keys with the phrase after the recovery = %d, want 400", code)
	}
	again := postJSON(engine, "/api/v0/auth/recover", map[string]string{
		"username": "old", "recoveryPhrase": "old-phrase", "newAuthKey": authKeyOf(7), "newRecoveryKey": authKeyOf(8),
	})
	if again.Code != http.StatusBadRequest {
		t.Errorf("the phrase again = %d %s, want 400", again.Code, again.Body)
	}
	if code := postJSON(engine, "/api/v0/auth/recover/keys", map[string]string{"username": "old", "recoveryKey": newRecoveryKey}).Code; code != http.StatusNotFound {
		t.Errorf("recover/keys with the new recovery key = %d, want 404 for no chat keys", code)
	}
	if code := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "old", "authKey": newKey}).Code; code != http.StatusOK {
		t.Errorf("the new auth key = %d, want 200", code)
	}
}
