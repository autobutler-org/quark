package authutil_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func checkRecovery(queries db.Querier, username, key string) error {
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
		Database: database, Files: vfs.NewMemVFS("files"), Username: "ada",
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
	phraseHash := dbtest.BcryptHash(t, "both-phrase")
	keyHash, err := authutil.HashKey(authKeyOf(9))
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
	set := func(username, key string, after func(db.Querier, int64) error) error {
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
	if err := set("ada", authKeyOf(9), func(db.Querier, int64) error { return failing }); !errors.Is(err, failing) {
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

	if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, Username: "cy", AuthKey: authKeyOf(3), SaltSecret: saltSecret, Files: vfs.NewMemVFS("files")}); err != nil {
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

// confirmRecoveryKey runs ConfirmRecoveryKey for userID behind guard and
// reports whether its AfterConfirm step ran.
func confirmRecoveryKey(database *db.DatabaseSqlc, guard *ratelimitutil.LoginGuard, userID int64, key string) (bool, error) {
	ran := false
	_, err := authutil.ConfirmRecoveryKey(context.Background(), database, authutil.ConfirmRecoveryKeyParams{
		UserID: userID, RecoveryKey: key, Guard: guard, ClientIP: "203.0.113.7",
		AfterConfirm: func(db.Querier, int64) error { ran = true; return nil },
	})
	return ran, err
}

// TestConfirmRecoveryKey wraps keys under the phrase an account has, and only
// that one (#3530): a wrong, missing or malformed key, or an account with no
// recovery key, is refused before the store step runs, and the right key
// runs it without replacing the stored key.
func TestConfirmRecoveryKey(t *testing.T) {
	database := setupWithKeys(t)
	queries := database.Queries
	addLegacy(t, queries)
	ada, old := userRow(t, queries, "ada"), userRow(t, queries, "old")

	for _, tc := range []struct {
		name   string
		userID int64
		key    string
		want   error
	}{
		{"wrong key", ada.ID, authKeyOf(8), authutil.ErrInvalidRecoveryPhrase},
		{"missing", ada.ID, "", authutil.ErrInvalidRecoveryKey},
		{"malformed", ada.ID, "not-base64", authutil.ErrInvalidRecoveryKey},
		{"no recovery key", old.ID, authKeyOf(9), authutil.ErrInvalidRecoveryPhrase},
		{"gone account", 9999, authKeyOf(9), authutil.ErrUserNotFound},
	} {
		ran, err := confirmRecoveryKey(database, nil, tc.userID, tc.key)
		if !errors.Is(err, tc.want) || ran {
			t.Errorf("%s: %v, stored %v, want %v and nothing stored", tc.name, err, ran, tc.want)
		}
	}

	ran, err := confirmRecoveryKey(database, nil, ada.ID, authKeyOf(9))
	if err != nil || !ran {
		t.Fatalf("right key: %v, stored %v, want the store step run", err, ran)
	}
	if row := userRow(t, queries, "ada"); row.RecoveryKeyHash != ada.RecoveryKeyHash {
		t.Error("confirming the key replaced it")
	}
	if err := checkRecovery(queries, "ada", authKeyOf(9)); err != nil {
		t.Errorf("the key stopped recovering the account: %v", err)
	}

	// A store step that fails rolls the transaction back with its error.
	refused := errors.New("refused")
	_, err = authutil.ConfirmRecoveryKey(context.Background(), database, authutil.ConfirmRecoveryKeyParams{
		UserID: ada.ID, RecoveryKey: authKeyOf(9),
		AfterConfirm: func(db.Querier, int64) error { return refused },
	})
	if !errors.Is(err, refused) {
		t.Errorf("failing store step: %v, want its error", err)
	}
}

// TestConfirmRecoveryKey_Replay replays a confirmation once the account's
// phrase has moved on: the old key no longer matches, so nothing is wrapped
// under a phrase the account stopped having.
func TestConfirmRecoveryKey_Replay(t *testing.T) {
	database := setupWithKeys(t)
	ada := userRow(t, database.Queries, "ada")
	if _, err := authutil.SetRecoveryKey(context.Background(), database, authutil.SetRecoveryKeyParams{UserID: ada.ID, RecoveryKey: authKeyOf(7)}); err != nil {
		t.Fatal(err)
	}
	if ran, err := confirmRecoveryKey(database, nil, ada.ID, authKeyOf(9)); !errors.Is(err, authutil.ErrInvalidRecoveryPhrase) || ran {
		t.Errorf("replayed old key: %v, stored %v, want refused and nothing stored", err, ran)
	}
}

// TestConfirmRecoveryKey_Lockout counts wrong keys toward the sign-in
// lockouts (#3578): once they lock the account, the right key is refused too,
// and so is a sign-in.
func TestConfirmRecoveryKey_Lockout(t *testing.T) {
	database := setupWithKeys(t)
	ada := userRow(t, database.Queries, "ada")
	now := time.Unix(1_700_000_000, 0)
	guard := lockoutGuard(&now)

	for i := range 3 {
		if _, err := confirmRecoveryKey(database, guard, ada.ID, authKeyOf(8)); !errors.Is(err, authutil.ErrInvalidRecoveryPhrase) {
			t.Fatalf("wrong key %d: %v", i+1, err)
		}
	}
	if ran, err := confirmRecoveryKey(database, guard, ada.ID, authKeyOf(9)); !isLocked(err) || ran {
		t.Errorf("right key while locked out: %v, stored %v, want the lockout and nothing stored", err, ran)
	}
	_, err := authutil.Login(context.Background(), database.Queries, authutil.LoginParams{
		Username: "ada", AuthKey: authKeyOf(1), Guard: guard, ClientIP: "203.0.113.7",
	})
	if !isLocked(err) {
		t.Errorf("sign-in after wrong recovery keys: %v, want the lockout", err)
	}
}

// lockoutGuard locks a pair or an account out after three failures, against a
// clock the test moves.
func lockoutGuard(now *time.Time) *ratelimitutil.LoginGuard {
	return ratelimitutil.NewLoginGuard(ratelimitutil.LoginGuardParams{
		Now:              func() time.Time { return *now },
		PairThreshold:    3,
		IPThreshold:      100,
		AccountThreshold: 3,
		BaseLockout:      time.Minute,
	})
}

// isLocked reports whether err is the guard's refusal.
func isLocked(err error) bool {
	var locked *authutil.TooManyAttemptsError
	return errors.As(err, &locked)
}
