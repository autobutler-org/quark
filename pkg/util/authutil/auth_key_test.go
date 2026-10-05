package authutil_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
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

func login(queries *db.Queries, username, password, authKey string) error {
	_, err := authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: username, Password: password, AuthKey: authKey, SaltSecret: saltSecret,
	})
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

// setupLegacy makes the founding admin "ada" the way a client that sends the
// raw password does.
func setupLegacy(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	database := newTestDB(t)
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "ada", Password: "long-enough"}); err != nil {
		t.Fatalf("Setup: %v", err)
	}
	return database
}

// TestCheckPassword_EmptyHashNeverMatches pins the fail-closed behavior an
// account without a password, or without an auth key, depends on.
func TestCheckPassword_EmptyHashNeverMatches(t *testing.T) {
	for _, secret := range []string{"", "long-enough", authKeyOf(1)} {
		if authutil.CheckPassword(secret, "") {
			t.Errorf("CheckPassword(%q, \"\") = true, want false", secret)
		}
	}
}

// TestGetSalt covers the three kinds of username: unknown, legacy and
// upgraded. Unknown and legacy get the same deterministic function, every call
// returns the same salt, and only the legacy account is flagged.
func TestGetSalt(t *testing.T) {
	database := setupLegacy(t)
	queries := database.Queries

	unknown, legacy := saltOf(t, queries, "nobody"), saltOf(t, queries, "ada")
	if unknown.Legacy || !legacy.Legacy {
		t.Errorf("legacy flags: unknown %v, legacy account %v; want false, true", unknown.Legacy, legacy.Legacy)
	}
	for name, got := range map[string]authutil.GetSaltResult{"nobody": unknown, "ada": legacy} {
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

	if err := login(queries, "ada", "long-enough", authKeyOf(1)); err != nil {
		t.Fatalf("upgrade: %v", err)
	}
	upgraded := saltOf(t, queries, "ada")
	if upgraded.Legacy || upgraded.Salt != legacy.Salt {
		t.Errorf("upgraded = %+v, want the salt %q it derived with and legacy false", upgraded, legacy.Salt)
	}
	if stored := userRow(t, queries, "ada").AuthSalt; stored != legacy.Salt {
		t.Errorf("stored salt = %q, want %q", stored, legacy.Salt)
	}

	// A stored salt wins over the secret, so losing the secret locks nobody out.
	other, err := authutil.GetSalt(context.Background(), queries, authutil.GetSaltParams{
		Username: "ada", SaltSecret: func() ([]byte, error) { return []byte("another secret"), nil },
	})
	if err != nil || other.Salt != legacy.Salt {
		t.Errorf("salt under a new secret = %q, %v; want the stored %q", other.Salt, err, legacy.Salt)
	}
}

// TestLogin_AuthKeyShapes walks one legacy account through the three login
// shapes: a key is refused before the upgrade, the upgrade keeps the password
// working, and a later upgrade attempt does not replace the stored key.
func TestLogin_AuthKeyShapes(t *testing.T) {
	database := setupLegacy(t)
	queries := database.Queries
	key, otherKey := authKeyOf(1), authKeyOf(2)

	if err := login(queries, "ada", "", key); err == nil {
		t.Fatal("an auth key signed in to an account that has none")
	}
	if err := login(queries, "ada", "wrong-password", key); err == nil {
		t.Fatal("an upgrade with a wrong password signed in")
	}
	if hash := userRow(t, queries, "ada").AuthKeyHash; hash != "" {
		t.Fatal("a refused upgrade stored an auth key")
	}
	if err := login(queries, "ada", "", "not-base64"); !errors.Is(err, authutil.ErrInvalidAuthKey) {
		t.Errorf("malformed key: err = %v, want ErrInvalidAuthKey", err)
	}
	if err := login(queries, "ada", "long-enough", base64.StdEncoding.EncodeToString([]byte("short"))); !errors.Is(err, authutil.ErrInvalidAuthKey) {
		t.Errorf("short key: err = %v, want ErrInvalidAuthKey", err)
	}
	if err := login(queries, "ada", "", ""); !errors.Is(err, authutil.ErrCredentialRequired) {
		t.Errorf("no credential: err = %v, want ErrCredentialRequired", err)
	}

	before := userRow(t, queries, "ada")
	if err := login(queries, "ada", "long-enough", key); err != nil {
		t.Fatalf("upgrade: %v", err)
	}
	after := userRow(t, queries, "ada")
	if after.PasswordHash != before.PasswordHash || after.AuthKeyHash == "" {
		t.Fatalf("upgrade left password hash changed=%v, auth key set=%v", after.PasswordHash != before.PasswordHash, after.AuthKeyHash != "")
	}
	if err := login(queries, "ada", "", key); err != nil {
		t.Errorf("auth key after upgrade: %v", err)
	}
	if err := login(queries, "ada", "long-enough", ""); err != nil {
		t.Errorf("legacy password after upgrade: %v", err)
	}
	if err := login(queries, "ada", "", otherKey); err == nil {
		t.Error("a wrong auth key signed in")
	}
	// An auth key is not a password, and a password is not an auth key.
	if err := login(queries, "ada", key, ""); err == nil {
		t.Error("the auth key signed in as the password")
	}

	if err := login(queries, "ada", "long-enough", otherKey); err != nil {
		t.Fatalf("second upgrade attempt should be a plain legacy login: %v", err)
	}
	if userRow(t, queries, "ada").AuthKeyHash != after.AuthKeyHash {
		t.Error("a second upgrade overwrote the stored auth key")
	}
}

// TestNewAccount_AuthKey makes an account each way an account is made, with
// an auth key in place of the password: it stores the salt GetSalt offered
// beforehand and an empty password hash that no password matches.
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
		if user.PasswordHash != "" || user.AuthKeyHash == "" || user.AuthSalt != salt {
			t.Errorf("%s: password hash %q, auth key set %v, salt %q; want \"\", true, %q", name, user.PasswordHash, user.AuthKeyHash != "", user.AuthSalt, salt)
		}
		if got := saltOf(t, queries, name); got.Legacy || got.Salt != salt {
			t.Errorf("%s: salt = %+v, want %q and legacy false", name, got, salt)
		}
		if err := login(queries, name, "", key); err != nil {
			t.Errorf("%s: auth key login: %v", name, err)
		}
		for _, password := range []string{"long-enough", key} {
			if err := login(queries, name, password, ""); err == nil {
				t.Errorf("%s: password %q signed in to an account with no password", name, password)
			}
		}
		if _, err := authutil.VerifyPassword(ctx, authutil.VerifyPasswordParams{Queries: queries, Username: name, Password: ""}); !errors.Is(err, authutil.ErrIncorrectPassword) {
			t.Errorf("%s: empty re-confirm: err = %v, want ErrIncorrectPassword", name, err)
		}
	}
}

// TestNewAccount_CredentialChoice checks every way of making an account
// refuses both credentials, neither, and a malformed key.
func TestNewAccount_CredentialChoice(t *testing.T) {
	ctx := context.Background()
	for _, tc := range []struct {
		name, password, authKey string
		want                    error
	}{
		{"both", "long-enough", authKeyOf(1), authutil.ErrCredentialConflict},
		{"neither", "", "", authutil.ErrCredentialRequired},
		{"malformed", "", "not base64!", authutil.ErrInvalidAuthKey},
		{"wrong length", "", base64.StdEncoding.EncodeToString(make([]byte, 31)), authutil.ErrInvalidAuthKey},
		{"url alphabet", "", base64.URLEncoding.EncodeToString(bytes.Repeat([]byte{0xff}, 32)), authutil.ErrInvalidAuthKey},
		{"short password", "short", "", authutil.ErrPasswordTooShort},
	} {
		database := newTestDB(t)
		if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "owner", Password: tc.password, AuthKey: tc.authKey, SaltSecret: saltSecret}); !errors.Is(err, tc.want) {
			t.Errorf("Setup %s: err = %v, want %v", tc.name, err, tc.want)
		}
		if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "owner", Password: "long-enough"}); err != nil {
			t.Fatal(err)
		}
		if _, err := authutil.RequestAccount(ctx, database.Queries, authutil.RequestAccountParams{Username: "asker", Password: tc.password, AuthKey: tc.authKey, SaltSecret: saltSecret, RequestsEnabled: true}); !errors.Is(err, tc.want) {
			t.Errorf("RequestAccount %s: err = %v, want %v", tc.name, err, tc.want)
		}
		if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, FilesDir: t.TempDir(), Username: "added", Password: tc.password, AuthKey: tc.authKey, SaltSecret: saltSecret}); !errors.Is(err, tc.want) {
			t.Errorf("CreateUser %s: err = %v, want %v", tc.name, err, tc.want)
		}
		if _, err := authutil.Recover(ctx, database, authutil.RecoverParams{Username: "owner", RecoveryPhrase: "x", NewPassword: tc.password, NewAuthKey: tc.authKey, SaltSecret: saltSecret}); !errors.Is(err, tc.want) {
			t.Errorf("Recover %s: err = %v, want %v", tc.name, err, tc.want)
		}
	}
}

// TestReconfirm_EitherCredential checks the shared gate behind re-confirmation
// and HTTP Basic takes the password or the auth key of an upgraded account in
// the one password slot, and nothing else.
func TestReconfirm_EitherCredential(t *testing.T) {
	ctx := context.Background()
	database := setupLegacy(t)
	queries := database.Queries
	key := authKeyOf(1)
	if _, _, err := authutil.ValidateBasicAuth(ctx, queries, "ada", key); err == nil {
		t.Fatal("Basic auth took an auth key before the account had one")
	}
	if err := login(queries, "ada", "long-enough", key); err != nil {
		t.Fatalf("upgrade: %v", err)
	}

	for _, tc := range []struct {
		secret string
		ok     bool
	}{
		{"long-enough", true},
		{key, true},
		{authKeyOf(2), false},
		{"", false},
	} {
		_, err := authutil.VerifyPassword(ctx, authutil.VerifyPasswordParams{Queries: queries, Username: "ada", Password: tc.secret})
		if (err == nil) != tc.ok || (!tc.ok && !errors.Is(err, authutil.ErrIncorrectPassword)) {
			t.Errorf("VerifyPassword(%q): err = %v, want ok=%v", tc.secret, err, tc.ok)
		}
		if _, _, err := authutil.ValidateBasicAuth(ctx, queries, "ada", tc.secret); (err == nil) != tc.ok {
			t.Errorf("ValidateBasicAuth(%q): err = %v, want ok=%v", tc.secret, err, tc.ok)
		}
	}
}

// TestRecover_NewPasswordClearsAuthKey checks a legacy recovery ends the auth
// key derived from the old password, which would otherwise still sign in.
func TestRecover_NewPasswordClearsAuthKey(t *testing.T) {
	ctx := context.Background()
	database := newTestDB(t)
	queries := database.Queries
	key := authKeyOf(1)
	setup, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "ada", Password: "long-enough"})
	if err != nil {
		t.Fatal(err)
	}
	if err := login(queries, "ada", "long-enough", key); err != nil {
		t.Fatalf("upgrade: %v", err)
	}

	if _, err := authutil.Recover(ctx, database, authutil.RecoverParams{Username: "ada", RecoveryPhrase: setup.RecoveryPhrase, NewPassword: "brand-new-password"}); err != nil {
		t.Fatalf("Recover: %v", err)
	}
	if err := login(queries, "ada", "", key); err == nil {
		t.Error("the old auth key still signs in after a password recovery")
	}
	if _, _, err := authutil.ValidateBasicAuth(ctx, queries, "ada", key); err == nil {
		t.Error("the old auth key still passes Basic auth after a password recovery")
	}
	if err := login(queries, "ada", "long-enough", ""); err == nil {
		t.Error("the old password still signs in")
	}
	if err := login(queries, "ada", "brand-new-password", ""); err != nil {
		t.Errorf("new password: %v", err)
	}
	if user := userRow(t, queries, "ada"); user.AuthKeyHash != "" || user.AuthSalt != "" {
		t.Errorf("auth key set %v, salt %q; want both cleared", user.AuthKeyHash != "", user.AuthSalt)
	}
	if got := saltOf(t, queries, "ada"); !got.Legacy {
		t.Error("a recovered legacy account should be offered an upgrade again")
	}
}

// TestRecover_NewAuthKeyClearsPassword checks a recovery with an auth key ends
// the old password and the old key, for a legacy account, which has no salt
// yet, and for an upgraded one, which keeps the salt it has.
func TestRecover_NewAuthKeyClearsPassword(t *testing.T) {
	ctx := context.Background()
	oldKey, newKey := authKeyOf(1), authKeyOf(2)
	for _, upgraded := range []bool{false, true} {
		database := newTestDB(t)
		queries := database.Queries
		setup, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "ada", Password: "long-enough"})
		if err != nil {
			t.Fatal(err)
		}
		if upgraded {
			if err := login(queries, "ada", "long-enough", oldKey); err != nil {
				t.Fatalf("upgrade: %v", err)
			}
		}
		offered := saltOf(t, queries, "ada").Salt

		if _, err := authutil.Recover(ctx, database, authutil.RecoverParams{Username: "ada", RecoveryPhrase: setup.RecoveryPhrase, NewAuthKey: newKey, SaltSecret: saltSecret}); err != nil {
			t.Fatalf("upgraded=%v Recover: %v", upgraded, err)
		}
		user := userRow(t, queries, "ada")
		if user.PasswordHash != "" || user.AuthSalt != offered {
			t.Errorf("upgraded=%v: password hash %q, salt %q; want \"\" and %q", upgraded, user.PasswordHash, user.AuthSalt, offered)
		}
		if err := login(queries, "ada", "", newKey); err != nil {
			t.Errorf("upgraded=%v new auth key: %v", upgraded, err)
		}
		if err := login(queries, "ada", "long-enough", ""); err == nil {
			t.Errorf("upgraded=%v: the old password still signs in", upgraded)
		}
		if err := login(queries, "ada", "", oldKey); err == nil {
			t.Errorf("upgraded=%v: the old auth key still signs in", upgraded)
		}
	}
}
