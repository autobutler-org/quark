package authutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

func checkRecovery(queries *db.Queries, username, phrase, key string) error {
	_, err := authutil.CheckRecovery(context.Background(), queries, authutil.CheckRecoveryParams{
		Username: username, RecoveryPhrase: phrase, RecoveryKey: key,
	})
	return err
}

// setupWithKeys makes the founding admin "ada" the way an updated client does:
// an auth key and a recovery key, and no phrase from the Quark.
func setupWithKeys(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	database := newTestDB(t)
	result, err := authutil.Setup(context.Background(), authutil.SetupParams{
		Database: database, FilesDir: t.TempDir(), Username: "ada",
		AuthKey: authKeyOf(1), RecoveryKey: authKeyOf(9), SaltSecret: saltSecret,
	})
	if err != nil {
		t.Fatalf("Setup: %v", err)
	}
	if result.RecoveryPhrase != "" {
		t.Errorf("setup with a recovery key returned phrase %q", result.RecoveryPhrase)
	}
	return database
}

// TestCheckRecovery_Secrets pins which secret recovers which account: a key
// only against the key hash, a phrase only while there is no key, and exactly
// one of the two per call.
func TestCheckRecovery_Secrets(t *testing.T) {
	queries := setupWithKeys(t).Queries
	row := userRow(t, queries, "ada")
	if row.RecoveryPhraseHash != "" || row.RecoveryKeyHash == "" {
		t.Fatalf("setup stored phrase %q key %q, want only a key", row.RecoveryPhraseHash, row.RecoveryKeyHash)
	}

	if err := checkRecovery(queries, "ada", "", authKeyOf(9)); err != nil {
		t.Errorf("right key: %v", err)
	}
	for name, tc := range map[string]struct {
		phrase, key string
		want        error
	}{
		"wrong key":    {"", authKeyOf(8), authutil.ErrInvalidRecoveryPhrase},
		"any phrase":   {"apple-bread-cloud-delta-eagle-flame", "", authutil.ErrInvalidRecoveryPhrase},
		"neither":      {"", "", authutil.ErrRecoverySecretRequired},
		"both":         {"apple", authKeyOf(9), authutil.ErrRecoverySecretRequired},
		"malformed":    {"", "not-base64", authutil.ErrInvalidRecoveryKey},
		"unknown user": {"", authKeyOf(9), authutil.ErrInvalidRecoveryPhrase},
	} {
		username := "ada"
		if name == "unknown user" {
			username = "nobody"
		}
		if err := checkRecovery(queries, username, tc.phrase, tc.key); !errors.Is(err, tc.want) {
			t.Errorf("%s: %v, want %v", name, err, tc.want)
		}
	}
}

// TestCheckRecovery_PhraseRefusedBesideKey is the fail-closed case: a row that
// somehow holds both hashes still refuses its phrase.
func TestCheckRecovery_PhraseRefusedBesideKey(t *testing.T) {
	queries := newTestDB(t).Queries
	const phrase = "apple-bread-cloud-delta-eagle-flame"
	phraseHash, _ := authutil.HashPassword(phrase)
	keyHash, _ := authutil.HashPassword(authKeyOf(9))
	if _, err := queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: "bob", RecoveryPhraseHash: phraseHash, RecoveryKeyHash: keyHash,
	}); err != nil {
		t.Fatal(err)
	}
	if err := checkRecovery(queries, "bob", phrase, ""); !errors.Is(err, authutil.ErrInvalidRecoveryPhrase) {
		t.Errorf("phrase beside a key = %v, want ErrInvalidRecoveryPhrase", err)
	}
}

// TestSetRecoveryKey rotates a legacy account to a recovery key. It needs the
// auth salt, refuses a malformed key, and rolls back with AfterSet.
func TestSetRecoveryKey(t *testing.T) {
	ctx := context.Background()
	database := setupLegacy(t)
	queries := database.Queries
	ada := userRow(t, queries, "ada")
	set := func(key string, after func(*db.Queries, int64) error) error {
		_, err := authutil.SetRecoveryKey(ctx, database, authutil.SetRecoveryKeyParams{UserID: ada.ID, RecoveryKey: key, AfterSet: after})
		return err
	}

	if err := set(authKeyOf(9), nil); !errors.Is(err, authutil.ErrNoAuthSalt) {
		t.Errorf("before an auth key = %v, want ErrNoAuthSalt", err)
	}
	if err := login(queries, "ada", "long-enough", authKeyOf(1)); err != nil {
		t.Fatal(err)
	}
	if !saltOf(t, queries, "ada").LegacyRecovery {
		t.Error("an account with only a phrase should read legacyRecovery")
	}
	if err := set("not-base64", nil); !errors.Is(err, authutil.ErrInvalidRecoveryKey) {
		t.Errorf("malformed = %v, want ErrInvalidRecoveryKey", err)
	}
	failing := errors.New("chat keys refused")
	if err := set(authKeyOf(9), func(*db.Queries, int64) error { return failing }); !errors.Is(err, failing) {
		t.Errorf("failing AfterSet = %v", err)
	}
	if row := userRow(t, queries, "ada"); row.RecoveryKeyHash != "" || row.RecoveryPhraseHash != ada.RecoveryPhraseHash {
		t.Error("a failed AfterSet left the recovery credentials changed")
	}

	if err := set(authKeyOf(9), nil); err != nil {
		t.Fatal(err)
	}
	if row := userRow(t, queries, "ada"); row.RecoveryPhraseHash != "" || row.RecoveryKeyHash == "" {
		t.Errorf("after rotation phrase %q key %q, want only a key", row.RecoveryPhraseHash, row.RecoveryKeyHash)
	}
	if saltOf(t, queries, "ada").LegacyRecovery || saltOf(t, queries, "nobody").LegacyRecovery {
		t.Error("a rotated account and an unknown username should both read legacyRecovery false")
	}
	result, err := authutil.Login(ctx, queries, authutil.LoginParams{Username: "ada", AuthKey: authKeyOf(1)})
	if err != nil || result.LegacyRecovery || result.RecoveryPhrase != "" {
		t.Errorf("login after rotation = %+v %v, want no phrase and legacyRecovery false", result, err)
	}
}

// TestRecover_NewRecoveryKey moves a legacy account to a recovery key in the
// same request that recovers it with the raw phrase.
func TestRecover_NewRecoveryKey(t *testing.T) {
	ctx := context.Background()
	database := newTestDB(t)
	setup, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "ada", Password: "long-enough"})
	if err != nil {
		t.Fatal(err)
	}
	recoverAda := func(params authutil.RecoverParams) error {
		params.Username, params.SaltSecret = "ada", saltSecret
		_, err := authutil.Recover(ctx, database, params)
		return err
	}

	if err := recoverAda(authutil.RecoverParams{RecoveryPhrase: setup.RecoveryPhrase, NewPassword: "brand-new-password", NewRecoveryKey: authKeyOf(9)}); !errors.Is(err, authutil.ErrRecoveryKeyNeedsAuthKey) {
		t.Errorf("new recovery key with a password = %v, want ErrRecoveryKeyNeedsAuthKey", err)
	}
	if err := recoverAda(authutil.RecoverParams{RecoveryPhrase: setup.RecoveryPhrase, NewAuthKey: authKeyOf(2), NewRecoveryKey: authKeyOf(9)}); err != nil {
		t.Fatal(err)
	}
	if err := checkRecovery(database.Queries, "ada", setup.RecoveryPhrase, ""); !errors.Is(err, authutil.ErrInvalidRecoveryPhrase) {
		t.Errorf("old phrase after rotation = %v, want ErrInvalidRecoveryPhrase", err)
	}
	if err := recoverAda(authutil.RecoverParams{RecoveryKey: authKeyOf(9), NewAuthKey: authKeyOf(3)}); err != nil {
		t.Errorf("recover with the new key: %v", err)
	}
	if err := login(database.Queries, "ada", "", authKeyOf(3)); err != nil {
		t.Errorf("login after key recovery: %v", err)
	}
}

// TestNewAccount_RecoveryKey covers the account-making rules: a recovery key
// only with an auth key, and an admin-created account that already has a key
// is handed no phrase at its first sign-in.
func TestNewAccount_RecoveryKey(t *testing.T) {
	ctx := context.Background()
	database := newTestDB(t)
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "ada", Password: "long-enough", RecoveryKey: authKeyOf(9)}); !errors.Is(err, authutil.ErrRecoveryKeyNeedsAuthKey) {
		t.Errorf("setup with a password and a recovery key = %v, want ErrRecoveryKeyNeedsAuthKey", err)
	}

	database = setupWithKeys(t)
	requested, err := authutil.RequestAccount(ctx, database.Queries, authutil.RequestAccountParams{
		Username: "bea", AuthKey: authKeyOf(2), RecoveryKey: authKeyOf(8), SaltSecret: saltSecret, RequestsEnabled: true,
	})
	if err != nil || requested.RecoveryPhrase != "" {
		t.Errorf("request with a recovery key = %+v %v, want no phrase", requested, err)
	}

	created, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, Username: "cy", AuthKey: authKeyOf(3), SaltSecret: saltSecret, FilesDir: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := authutil.SetRecoveryKey(ctx, database, authutil.SetRecoveryKeyParams{UserID: created.UserID, RecoveryKey: authKeyOf(7)}); err != nil {
		t.Fatal(err)
	}
	result, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "cy", AuthKey: authKeyOf(3)})
	if err != nil || result.RecoveryPhrase != "" || result.LegacyRecovery {
		t.Errorf("first login with a recovery key = %+v %v, want no phrase and legacyRecovery false", result, err)
	}
	if row := userRow(t, database.Queries, "cy"); row.RecoveryPhraseHash != "" {
		t.Error("first login gave an account with a recovery key a phrase")
	}
}
