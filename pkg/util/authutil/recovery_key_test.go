package authutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

func checkRecovery(queries *db.Queries, username, key string) error {
	_, err := authutil.CheckRecovery(context.Background(), queries, authutil.CheckRecoveryParams{
		Username: username, RecoveryKey: key,
	})
	return err
}

// setupWithKeys makes the founding admin "ada" the way the app does: an auth
// key and a recovery key, and no phrase from the Quark.
func setupWithKeys(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	database := newTestDB(t)
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{
		Database: database, FilesDir: t.TempDir(), Username: "ada",
		AuthKey: authKeyOf(1), RecoveryKey: authKeyOf(9), SaltSecret: saltSecret,
	}); err != nil {
		t.Fatalf("Setup: %v", err)
	}
	return database
}

// TestCheckRecovery_Keys pins which key recovers which account: only the
// stored key, and nothing for an account that has none.
func TestCheckRecovery_Keys(t *testing.T) {
	queries := setupWithKeys(t).Queries
	addLegacy(t, queries)
	if row := userRow(t, queries, "ada"); row.RecoveryPhraseHash != "" || row.RecoveryKeyHash == "" {
		t.Fatalf("setup stored phrase %q key %q, want only a key", row.RecoveryPhraseHash, row.RecoveryKeyHash)
	}

	if err := checkRecovery(queries, "ada", authKeyOf(9)); err != nil {
		t.Errorf("right key: %v", err)
	}
	for _, tc := range []struct {
		name, username, key string
		want                error
	}{
		{"wrong key", "ada", authKeyOf(8), authutil.ErrInvalidRecoveryPhrase},
		{"missing", "ada", "", authutil.ErrRecoverySecretRequired},
		{"malformed", "ada", "not-base64", authutil.ErrInvalidRecoveryKey},
		{"unknown user", "nobody", authKeyOf(9), authutil.ErrInvalidRecoveryPhrase},
		{"no recovery key", "old", authKeyOf(9), authutil.ErrInvalidRecoveryPhrase},
	} {
		if err := checkRecovery(queries, tc.username, tc.key); !errors.Is(err, tc.want) {
			t.Errorf("%s: %v, want %v", tc.name, err, tc.want)
		}
	}
}

// TestCheckRecovery_Phrase pins the raw phrase to accounts that have no
// recovery key yet (#2430): it recovers "old", and nothing for an account that
// has a key, even one that still holds a phrase hash.
func TestCheckRecovery_Phrase(t *testing.T) {
	ctx := context.Background()
	queries := setupWithKeys(t).Queries
	addLegacy(t, queries)
	phraseHash, err := authutil.HashPassword("both-phrase")
	if err != nil {
		t.Fatal(err)
	}
	keyHash, err := authutil.HashPassword(authKeyOf(9))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := queries.CreateUser(ctx, db.CreateUserParams{Username: "both", RecoveryPhraseHash: phraseHash, RecoveryKeyHash: keyHash}); err != nil {
		t.Fatal(err)
	}
	check := func(username, phrase, key string) error {
		_, err := authutil.CheckRecovery(ctx, queries, authutil.CheckRecoveryParams{Username: username, RecoveryPhrase: phrase, RecoveryKey: key})
		return err
	}

	if err := check("old", " OLD-phrase ", ""); err != nil {
		t.Errorf("legacy phrase: %v", err)
	}
	for _, tc := range []struct {
		name, username, phrase, key string
		want                        error
	}{
		{"wrong phrase", "old", "other-phrase", "", authutil.ErrInvalidRecoveryPhrase},
		{"phrase of an account with a key", "both", "both-phrase", "", authutil.ErrInvalidRecoveryPhrase},
		{"unknown user", "nobody", "old-phrase", "", authutil.ErrInvalidRecoveryPhrase},
		{"phrase and key", "old", "old-phrase", authKeyOf(9), authutil.ErrRecoverySecretRequired},
	} {
		if err := check(tc.username, tc.phrase, tc.key); !errors.Is(err, tc.want) {
			t.Errorf("%s: %v, want %v", tc.name, err, tc.want)
		}
	}
}

// TestRecover_LegacyPhrase recovers "old" once with its raw phrase and a new
// phrase's key (#2430): both keys are stored with the salt GetSalt offered,
// both raw-secret hashes are cleared, and the phrase never recovers again. A
// phrase without both new keys is an old app's recovery.
func TestRecover_LegacyPhrase(t *testing.T) {
	ctx := context.Background()
	database := setupAda(t)
	queries := database.Queries
	addLegacy(t, queries)
	offered := saltOf(t, queries, "old").Salt
	recoverOld := func(phrase, newAuthKey, newRecoveryKey string) error {
		_, err := authutil.Recover(ctx, database, authutil.RecoverParams{
			Username: "old", RecoveryPhrase: phrase, NewAuthKey: newAuthKey, NewRecoveryKey: newRecoveryKey, SaltSecret: saltSecret,
		})
		return err
	}

	for _, tc := range []struct{ name, authKey, recoveryKey string }{
		{"no new recovery key", authKeyOf(5), ""},
		{"no new auth key", "", authKeyOf(6)},
	} {
		if err := recoverOld("old-phrase", tc.authKey, tc.recoveryKey); !errors.Is(err, authutil.ErrAppTooOld) {
			t.Errorf("%s: %v, want ErrAppTooOld", tc.name, err)
		}
	}
	if err := recoverOld("old-phrase", authKeyOf(5), authKeyOf(6)); err != nil {
		t.Fatalf("legacy recovery: %v", err)
	}
	user := userRow(t, queries, "old")
	if user.PasswordHash != "" || user.RecoveryPhraseHash != "" {
		t.Errorf("kept password hash %q phrase hash %q, want both cleared", user.PasswordHash, user.RecoveryPhraseHash)
	}
	if user.AuthSalt != offered || !authutil.CheckPassword(authKeyOf(5), user.AuthKeyHash) || !authutil.CheckPassword(authKeyOf(6), user.RecoveryKeyHash) {
		t.Errorf("salt %q, want %q and both new keys stored", user.AuthSalt, offered)
	}
	if err := recoverOld("old-phrase", authKeyOf(7), authKeyOf(8)); !errors.Is(err, authutil.ErrInvalidRecoveryPhrase) {
		t.Errorf("the phrase again: %v, want ErrInvalidRecoveryPhrase", err)
	}
	if err := checkRecovery(queries, "old", authKeyOf(6)); err != nil {
		t.Errorf("the new recovery key: %v", err)
	}
	if err := login(queries, "old", authKeyOf(5)); err != nil {
		t.Errorf("the new auth key: %v", err)
	}
}

// TestSetRecoveryKey gives an account with no recovery key one, as the app
// does at a sign-in that reads legacyRecovery. It needs the auth salt, refuses
// a malformed key, and rolls back with AfterSet.
func TestSetRecoveryKey(t *testing.T) {
	ctx := context.Background()
	database := setupAda(t)
	queries := database.Queries
	addLegacy(t, queries)
	set := func(username, key string, after func(*db.Queries, int64) error) error {
		_, err := authutil.SetRecoveryKey(ctx, database, authutil.SetRecoveryKeyParams{UserID: userRow(t, queries, username).ID, RecoveryKey: key, AfterSet: after})
		return err
	}

	if err := set("old", authKeyOf(9), nil); !errors.Is(err, authutil.ErrNoAuthSalt) {
		t.Errorf("without an auth key = %v, want ErrNoAuthSalt", err)
	}
	if !saltOf(t, queries, "ada").LegacyRecovery {
		t.Error("an account with no recovery key should read legacyRecovery")
	}
	if err := set("ada", "not-base64", nil); !errors.Is(err, authutil.ErrInvalidRecoveryKey) {
		t.Errorf("malformed = %v, want ErrInvalidRecoveryKey", err)
	}
	failing := errors.New("chat keys refused")
	if err := set("ada", authKeyOf(9), func(*db.Queries, int64) error { return failing }); !errors.Is(err, failing) {
		t.Errorf("failing AfterSet = %v", err)
	}
	if row := userRow(t, queries, "ada"); row.RecoveryKeyHash != "" {
		t.Error("a failed AfterSet left a recovery key")
	}

	if err := set("ada", authKeyOf(9), nil); err != nil {
		t.Fatal(err)
	}
	if err := checkRecovery(queries, "ada", authKeyOf(9)); err != nil {
		t.Errorf("recover with the set key: %v", err)
	}
	if saltOf(t, queries, "ada").LegacyRecovery || saltOf(t, queries, "nobody").LegacyRecovery {
		t.Error("an account with a recovery key and an unknown username should both read legacyRecovery false")
	}
	result, err := authutil.Login(ctx, queries, authutil.LoginParams{Username: "ada", AuthKey: authKeyOf(1)})
	if err != nil || result.LegacyRecovery {
		t.Errorf("login after the key = %+v %v, want legacyRecovery false", result, err)
	}
}

// TestNewAccount_RecoveryKey covers the recovery credential a new account
// starts with: the key it was sent, or none, and never a phrase.
func TestNewAccount_RecoveryKey(t *testing.T) {
	ctx := context.Background()
	database := setupWithKeys(t)
	if _, err := authutil.RequestAccount(ctx, database.Queries, authutil.RequestAccountParams{
		Username: "bea", AuthKey: authKeyOf(2), RecoveryKey: authKeyOf(8), SaltSecret: saltSecret, RequestsEnabled: true,
	}); err != nil {
		t.Fatal(err)
	}
	// The key matches, so only the pending status refuses it.
	if err := checkRecovery(database.Queries, "bea", authKeyOf(8)); !errors.Is(err, authutil.ErrAccountPending) {
		t.Errorf("requested account's recovery key: %v, want ErrAccountPending", err)
	}
	if _, err := authutil.RequestAccount(ctx, database.Queries, authutil.RequestAccountParams{
		Username: "bad", AuthKey: authKeyOf(2), RecoveryKey: "not-base64", SaltSecret: saltSecret, RequestsEnabled: true,
	}); !errors.Is(err, authutil.ErrInvalidRecoveryKey) {
		t.Errorf("malformed recovery key = %v, want ErrInvalidRecoveryKey", err)
	}

	if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, Username: "cy", AuthKey: authKeyOf(3), SaltSecret: saltSecret, FilesDir: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	result, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "cy", AuthKey: authKeyOf(3)})
	if err != nil || !result.LegacyRecovery {
		t.Errorf("first login of an admin-created account = %+v %v, want legacyRecovery true", result, err)
	}
	for _, name := range []string{"ada", "bea", "cy"} {
		if row := userRow(t, database.Queries, name); row.RecoveryPhraseHash != "" {
			t.Errorf("%s has a phrase hash", name)
		}
	}
}
