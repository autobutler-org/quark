package authutil_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// saltSecret stands in for the install's salt secret.
func saltSecret() ([]byte, error) {
	return bytes.Repeat([]byte{7}, 32), nil
}

// authKeyOf returns a well-formed auth key: the base64 of 32 bytes of fill.
func authKeyOf(fill byte) string {
	return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{fill}, 32))
}

func saltOf(t *testing.T, queries *db.Queries, username string) authutil.GetSaltResult {
	t.Helper()
	result, err := authutil.GetSalt(context.Background(), queries, authutil.GetSaltParams{Username: username, SaltSecret: saltSecret})
	if err != nil {
		t.Fatalf("GetSalt(%q): %v", username, err)
	}
	return result
}

func login(queries *db.Queries, username, authKey string) error {
	_, err := authutil.Login(context.Background(), queries, authutil.LoginParams{Username: username, AuthKey: authKey})
	return err
}

func userRow(t *testing.T, queries *db.Queries, username string) db.User {
	t.Helper()
	user, err := queries.GetUserByUsername(context.Background(), username)
	if err != nil {
		t.Fatal(err)
	}
	return user
}

// setupAda makes the founding admin "ada" with authKeyOf(1) and no recovery
// key, as an admin-created account starts out.
func setupAda(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	database := newTestDB(t)
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "ada", AuthKey: authKeyOf(1), SaltSecret: saltSecret}); err != nil {
		t.Fatalf("Setup: %v", err)
	}
	return database
}

// addLegacy adds "old", an account from before auth keys: the hashes of the
// password "old-password" and the phrase "old-phrase", and no keys.
func addLegacy(t *testing.T, queries *db.Queries) {
	t.Helper()
	passwordHash, err := authutil.HashPassword("old-password")
	if err != nil {
		t.Fatal(err)
	}
	phraseHash, err := authutil.HashPassword("old-phrase")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := queries.CreateUser(context.Background(), db.CreateUserParams{Username: "old", PasswordHash: passwordHash, RecoveryPhraseHash: phraseHash}); err != nil {
		t.Fatal(err)
	}
}

// TestCheckPassword_EmptyHashNeverMatches pins the fail-closed behavior an
// account without an auth key or a recovery key depends on.
func TestCheckPassword_EmptyHashNeverMatches(t *testing.T) {
	for _, secret := range []string{"", "long-enough", authKeyOf(1)} {
		if authutil.CheckPassword(secret, "") {
			t.Errorf("CheckPassword(%q, \"\") = true, want false", secret)
		}
	}
}

// TestRefuseRawSecrets pins the shared refusal: any set legacy field is a 426
// carrying the update-the-app sentence, and none set passes.
func TestRefuseRawSecrets(t *testing.T) {
	if err := authutil.RefuseRawSecrets("", ""); err != nil {
		t.Errorf("no raw secret: %v", err)
	}
	err := authutil.RefuseRawSecrets("", "a password")
	if !errors.Is(err, authutil.ErrAppTooOld) {
		t.Fatalf("raw secret: %v, want ErrAppTooOld", err)
	}
	httpErr, ok := errors.AsType[*serverutil.HttpError](err)
	if !ok || httpErr.StatusCode != http.StatusUpgradeRequired {
		t.Errorf("ErrAppTooOld = %#v, want a 426 HttpError", err)
	}
}

// TestGetSalt covers the three kinds of username: unknown, legacy and moved
// to keys. Unknown and legacy get the same deterministic function, every call
// returns the same salt, and only the legacy account is flagged.
func TestGetSalt(t *testing.T) {
	database := setupAda(t)
	queries := database.Queries
	addLegacy(t, queries)

	unknown, legacy, ada := saltOf(t, queries, "nobody"), saltOf(t, queries, "old"), saltOf(t, queries, "ada")
	if unknown.Legacy || unknown.LegacyRecovery {
		t.Errorf("unknown = %+v, want it to look moved to keys", unknown)
	}
	if !legacy.Legacy || !legacy.LegacyRecovery {
		t.Errorf("legacy = %+v, want both flags", legacy)
	}
	if ada.Legacy || !ada.LegacyRecovery {
		t.Errorf("ada = %+v, want legacy false and legacyRecovery true until she has a recovery key", ada)
	}
	for name, got := range map[string]authutil.GetSaltResult{"nobody": unknown, "old": legacy, "ada": ada} {
		if raw, err := base64.StdEncoding.DecodeString(got.Salt); err != nil || len(raw) != 16 {
			t.Errorf("%s salt %q is not the base64 of 16 bytes", name, got.Salt)
		}
		if again := saltOf(t, queries, name); again != got {
			t.Errorf("%s salt changed between calls: %v then %v", name, got, again)
		}
	}
	if unknown.Salt == legacy.Salt {
		t.Error("two usernames got the same salt")
	}
	if stored := userRow(t, queries, "ada").AuthSalt; stored != ada.Salt {
		t.Errorf("stored salt = %q, want %q", stored, ada.Salt)
	}

	// A stored salt wins over the secret, so losing the secret locks nobody out.
	other, err := authutil.GetSalt(context.Background(), queries, authutil.GetSaltParams{
		Username: "ada", SaltSecret: func() ([]byte, error) { return []byte("another secret"), nil },
	})
	if err != nil || other.Salt != ada.Salt {
		t.Errorf("salt under a new secret = %q, %v; want the stored %q", other.Salt, err, ada.Salt)
	}
}

// TestLogin_AuthKey signs in with the key alone: the right key works, a wrong
// or malformed one does not, and an account with no auth key takes none.
func TestLogin_AuthKey(t *testing.T) {
	database := setupAda(t)
	queries := database.Queries
	addLegacy(t, queries)

	result, err := authutil.Login(context.Background(), queries, authutil.LoginParams{Username: "ada", AuthKey: authKeyOf(1)})
	if err != nil || result.SessionToken == "" || !result.LegacyRecovery {
		t.Fatalf("login = %+v %v, want a session and legacyRecovery true", result, err)
	}
	if err := login(queries, "ada", authKeyOf(2)); err == nil {
		t.Error("a wrong auth key signed in")
	}
	for _, key := range []string{"", "not-base64", base64.StdEncoding.EncodeToString([]byte("short"))} {
		if err := login(queries, "ada", key); !errors.Is(err, authutil.ErrInvalidAuthKey) {
			t.Errorf("key %q: err = %v, want ErrInvalidAuthKey", key, err)
		}
	}
	for _, key := range []string{authKeyOf(0), authKeyOf(1)} {
		if err := login(queries, "old", key); err == nil {
			t.Errorf("key %q signed in to an account with no auth key", key)
		}
	}
	if user := userRow(t, queries, "old"); user.AuthKeyHash != "" {
		t.Error("a refused sign-in stored an auth key")
	}
}

// TestLogin_Upgrade moves "old" to an auth key through the sign-in form
// (#2430): the password beside the key upgrades it once, storing the salt
// GetSalt offered and clearing the password hash, so the password stops
// counting. An account that has a key is checked by it, whatever password is
// beside it, and a password alone is ErrAppTooOld.
func TestLogin_Upgrade(t *testing.T) {
	ctx := context.Background()
	database := setupAda(t)
	queries := database.Queries
	addLegacy(t, queries)
	offered := saltOf(t, queries, "old").Salt
	signIn := func(username, password, key string) error {
		_, err := authutil.Login(ctx, queries, authutil.LoginParams{Username: username, Password: password, AuthKey: key, SaltSecret: saltSecret})
		return err
	}

	if err := signIn("old", "wrong-password", authKeyOf(5)); err == nil {
		t.Error("a wrong password upgraded the account")
	}
	if err := signIn("old", "old-password", ""); !errors.Is(err, authutil.ErrAppTooOld) {
		t.Errorf("password alone: %v, want ErrAppTooOld", err)
	}
	if user := userRow(t, queries, "old"); user.AuthKeyHash != "" || user.PasswordHash == "" {
		t.Fatal("a refused sign-in changed the account")
	}

	if err := signIn("old", "old-password", authKeyOf(5)); err != nil {
		t.Fatalf("upgrade: %v", err)
	}
	user := userRow(t, queries, "old")
	if user.PasswordHash != "" || user.AuthSalt != offered || !authutil.CheckPassword(authKeyOf(5), user.AuthKeyHash) {
		t.Errorf("after the upgrade password hash %q salt %q, want cleared and %q, and the key stored", user.PasswordHash, user.AuthSalt, offered)
	}
	if err := signIn("old", "old-password", authKeyOf(6)); err == nil {
		t.Error("the password beside a wrong key signed in after the upgrade")
	}
	if err := signIn("old", "old-password", ""); !errors.Is(err, authutil.ErrAppTooOld) {
		t.Errorf("password alone after the upgrade: %v, want ErrAppTooOld", err)
	}
	if err := login(queries, "old", authKeyOf(5)); err != nil {
		t.Errorf("the upgraded key: %v", err)
	}
	if err := signIn("ada", "anything", authKeyOf(1)); err != nil {
		t.Errorf("a password beside the right key of an upgraded account: %v", err)
	}
}

// TestLogin_UpgradeWriteFails refuses the sign-in when the upgrade's write
// does not land, and leaves the account on its password with no session.
func TestLogin_UpgradeWriteFails(t *testing.T) {
	ctx := context.Background()
	database := setupAda(t)
	queries := database.Queries
	addLegacy(t, queries)
	if _, err := database.Db.Exec(`CREATE TRIGGER refuse_upgrade BEFORE UPDATE OF auth_key_hash ON users
		BEGIN SELECT RAISE(ABORT, 'disk full'); END`); err != nil {
		t.Fatal(err)
	}

	result, err := authutil.Login(ctx, queries, authutil.LoginParams{Username: "old", Password: "old-password", AuthKey: authKeyOf(5), SaltSecret: saltSecret})
	if err == nil {
		t.Fatalf("login = %+v, want the failed upgrade to refuse it", result)
	}
	if httpErr, ok := errors.AsType[*serverutil.HttpError](err); !ok || httpErr.StatusCode != http.StatusInternalServerError {
		t.Errorf("err = %#v, want a 500 HttpError", err)
	}
	user := userRow(t, queries, "old")
	if user.AuthKeyHash != "" || user.PasswordHash == "" {
		t.Error("a failed upgrade changed the account")
	}
	if sessions, err := queries.ListActiveSessionsForUser(ctx, user.ID); err != nil || len(sessions) != 0 {
		t.Errorf("sessions = %d %v, want none", len(sessions), err)
	}
}

// TestNewAccount_AuthKey makes an account each way an account is made: it
// stores the salt GetSalt offered beforehand and no raw-secret hash.
func TestNewAccount_AuthKey(t *testing.T) {
	ctx := context.Background()
	key := authKeyOf(3)
	database := newTestDB(t)
	queries := database.Queries
	offered := map[string]string{}
	for _, name := range []string{"owner", "asker", "added"} {
		offered[name] = saltOf(t, queries, name).Salt
	}

	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "owner", AuthKey: key, SaltSecret: saltSecret}); err != nil {
		t.Fatalf("Setup: %v", err)
	}
	if _, err := authutil.RequestAccount(ctx, queries, authutil.RequestAccountParams{Username: "asker", AuthKey: key, SaltSecret: saltSecret, RequestsEnabled: true}); err != nil {
		t.Fatalf("RequestAccount: %v", err)
	}
	if _, err := authutil.ApproveRequest(ctx, authutil.ApproveRequestParams{Database: database, Username: "asker", FilesDir: t.TempDir()}); err != nil {
		t.Fatalf("ApproveRequest: %v", err)
	}
	if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, FilesDir: t.TempDir(), Username: "added", AuthKey: key, SaltSecret: saltSecret}); err != nil {
		t.Fatalf("CreateUser: %v", err)
	}

	for name, salt := range offered {
		user := userRow(t, queries, name)
		if user.PasswordHash != "" || user.RecoveryPhraseHash != "" || user.AuthKeyHash == "" || user.AuthSalt != salt {
			t.Errorf("%s: password hash %q, phrase hash %q, auth key set %v, salt %q; want \"\", \"\", true, %q",
				name, user.PasswordHash, user.RecoveryPhraseHash, user.AuthKeyHash != "", user.AuthSalt, salt)
		}
		if got := saltOf(t, queries, name); got.Legacy || got.Salt != salt {
			t.Errorf("%s: salt = %+v, want %q and legacy false", name, got, salt)
		}
		if err := login(queries, name, key); err != nil {
			t.Errorf("%s: auth key login: %v", name, err)
		}
		if _, err := authutil.VerifyPassword(ctx, authutil.VerifyPasswordParams{Queries: queries, Username: name, Password: ""}); !errors.Is(err, authutil.ErrIncorrectPassword) {
			t.Errorf("%s: empty re-confirm: err = %v, want ErrIncorrectPassword", name, err)
		}
	}
}

// TestNewAccount_MalformedKey checks every way of making an account, and a
// recovery, refuses a missing or malformed auth key.
func TestNewAccount_MalformedKey(t *testing.T) {
	ctx := context.Background()
	for name, key := range map[string]string{
		"neither":      "",
		"malformed":    "not base64!",
		"wrong length": base64.StdEncoding.EncodeToString(make([]byte, 31)),
		"url alphabet": base64.URLEncoding.EncodeToString(bytes.Repeat([]byte{0xff}, 32)),
	} {
		database := newTestDB(t)
		if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "owner", AuthKey: key, SaltSecret: saltSecret}); !errors.Is(err, authutil.ErrInvalidAuthKey) {
			t.Errorf("Setup %s: err = %v, want ErrInvalidAuthKey", name, err)
		}
		if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "owner", AuthKey: authKeyOf(1), SaltSecret: saltSecret}); err != nil {
			t.Fatal(err)
		}
		if _, err := authutil.RequestAccount(ctx, database.Queries, authutil.RequestAccountParams{Username: "asker", AuthKey: key, SaltSecret: saltSecret, RequestsEnabled: true}); !errors.Is(err, authutil.ErrInvalidAuthKey) {
			t.Errorf("RequestAccount %s: err = %v, want ErrInvalidAuthKey", name, err)
		}
		if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, FilesDir: t.TempDir(), Username: "added", AuthKey: key, SaltSecret: saltSecret}); !errors.Is(err, authutil.ErrInvalidAuthKey) {
			t.Errorf("CreateUser %s: err = %v, want ErrInvalidAuthKey", name, err)
		}
		if _, err := authutil.Recover(ctx, database, authutil.RecoverParams{Username: "owner", RecoveryKey: authKeyOf(9), NewAuthKey: key, SaltSecret: saltSecret}); !errors.Is(err, authutil.ErrInvalidAuthKey) {
			t.Errorf("Recover %s: err = %v, want ErrInvalidAuthKey", name, err)
		}
	}
}

// TestReconfirm_AuthKeyOnly checks the shared gate behind re-confirmation and
// HTTP Basic: the account's auth key passes, a wrong or empty one is a wrong
// password, and a raw password is ErrAppTooOld before any lookup (#2430).
func TestReconfirm_AuthKeyOnly(t *testing.T) {
	ctx := context.Background()
	database := setupAda(t)
	queries := database.Queries

	for _, tc := range []struct {
		username, secret string
		want             error
	}{
		{"ada", authKeyOf(1), nil},
		{"ada", authKeyOf(2), authutil.ErrIncorrectPassword},
		{"ada", "", authutil.ErrIncorrectPassword},
		{"ada", "long-enough", authutil.ErrAppTooOld},
		{"nobody", "long-enough", authutil.ErrAppTooOld},
	} {
		_, err := authutil.VerifyPassword(ctx, authutil.VerifyPasswordParams{Queries: queries, Username: tc.username, Password: tc.secret})
		if !errors.Is(err, tc.want) {
			t.Errorf("VerifyPassword(%s, %q): err = %v, want %v", tc.username, tc.secret, err, tc.want)
		}
		// Basic says "invalid credentials" where VerifyPassword names the error,
		// but agrees on what passes and on what is too old.
		_, _, err = authutil.ValidateBasicAuth(ctx, queries, tc.username, tc.secret)
		if (err == nil) != (tc.want == nil) || errors.Is(err, authutil.ErrAppTooOld) != errors.Is(tc.want, authutil.ErrAppTooOld) {
			t.Errorf("ValidateBasicAuth(%s, %q): err = %v, want like %v", tc.username, tc.secret, err, tc.want)
		}
	}
}

// TestRecover_NewAuthKey checks a recovery replaces the auth key and keeps
// the salt the account already had.
func TestRecover_NewAuthKey(t *testing.T) {
	ctx := context.Background()
	database := setupWithKeys(t)
	queries := database.Queries
	salt := userRow(t, queries, "ada").AuthSalt

	if _, err := authutil.Recover(ctx, database, authutil.RecoverParams{Username: "ada", RecoveryKey: authKeyOf(9), NewAuthKey: authKeyOf(2), SaltSecret: saltSecret}); err != nil {
		t.Fatalf("Recover: %v", err)
	}
	if user := userRow(t, queries, "ada"); user.AuthSalt != salt {
		t.Errorf("salt %q, want the kept %q", user.AuthSalt, salt)
	}
	if err := login(queries, "ada", authKeyOf(2)); err != nil {
		t.Errorf("new auth key: %v", err)
	}
	if err := login(queries, "ada", authKeyOf(1)); err == nil {
		t.Error("the old auth key still signs in")
	}
	if _, _, err := authutil.ValidateBasicAuth(ctx, queries, "ada", authKeyOf(1)); err == nil {
		t.Error("the old auth key still passes Basic auth")
	}
}
