package authutil_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// --- Unit tests ---

// TestHashKey_AndCheck: a key is stored as "sha256:" and its hex digest, which
// only that key matches (#2765).
func TestHashKey_AndCheck(t *testing.T) {
	key := dbtest.AuthKey("correct-horse-battery")
	hash, err := authutil.HashKey(key)
	if err != nil {
		t.Fatalf("HashKey failed: %v", err)
	}
	sum := sha256.Sum256([]byte(key))
	if want := "sha256:" + hex.EncodeToString(sum[:]); hash != want {
		t.Errorf("HashKey = %q, want %q", hash, want)
	}
	if !authutil.CheckPassword(key, hash) {
		t.Error("CheckPassword should return true for the key")
	}
	for _, wrong := range []string{dbtest.AuthKey("wrong-password"), "", hash} {
		if authutil.CheckPassword(wrong, hash) {
			t.Errorf("CheckPassword(%q) = true, want false", wrong)
		}
	}
}

// TestHashKey_RefusesWhatIsNotAKey: only the base64 of 32 bytes takes the fast
// hash, so a secret a person chose can never be stored under it (#2765).
func TestHashKey_RefusesWhatIsNotAKey(t *testing.T) {
	for _, secret := range []string{
		"",
		"correct-horse-battery",
		base64.StdEncoding.EncodeToString(make([]byte, 31)),
		base64.StdEncoding.EncodeToString(make([]byte, 33)),
		base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0xff}, 32)),
	} {
		if hash, err := authutil.HashKey(secret); err == nil || hash != "" {
			t.Errorf("HashKey(%q) = %q, %v, want it refused", secret, hash, err)
		}
	}
}

// TestCheckPassword_Bcrypt: a hash that is not HashKey's is checked as bcrypt,
// which is what a legacy account's password and phrase are stored under.
func TestCheckPassword_Bcrypt(t *testing.T) {
	hash := dbtest.BcryptHash(t, "correct-horse-battery")
	if !authutil.CheckPassword("correct-horse-battery", hash) {
		t.Error("CheckPassword should return true for the right password")
	}
	if authutil.CheckPassword("wrong-password", hash) {
		t.Error("CheckPassword should return false for a wrong password")
	}
}

func TestGenerateSessionToken(t *testing.T) {
	token1, err := authutil.GenerateSessionToken()
	if err != nil {
		t.Fatalf("GenerateSessionToken failed: %v", err)
	}
	token2, err := authutil.GenerateSessionToken()
	if err != nil {
		t.Fatalf("GenerateSessionToken failed: %v", err)
	}
	if token1 == "" || token2 == "" {
		t.Error("Expected non-empty tokens")
	}
	if token1 == token2 {
		t.Error("Expected unique tokens, got duplicates")
	}
	if len(token1) != 64 {
		t.Errorf("Expected 64-char hex token, got len %d", len(token1))
	}
}

// --- Integration tests (real SQLite, full flow) ---

func TestIsSetupComplete_FreshDB(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	complete, err := authutil.IsSetupComplete(context.Background(), queries)
	if err != nil {
		t.Fatalf("IsSetupComplete failed: %v", err)
	}
	if complete {
		t.Error("Expected setup not complete on fresh DB")
	}
}

func TestSetup_Success(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	result, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("supersecret"), SaltSecret: dbtest.SaltSecret,
	})
	if err != nil {
		t.Fatalf("Setup failed: %v", err)
	}
	if result.SessionToken == "" {
		t.Error("Expected non-empty session token")
	}

	// Setup should now be complete
	complete, _ := authutil.IsSetupComplete(context.Background(), queries)
	if !complete {
		t.Error("Expected setup to be complete after Setup()")
	}
}

func TestSetup_CannotRunTwice(t *testing.T) {
	database := newTestDB(t)
	_, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("supersecret"), SaltSecret: dbtest.SaltSecret,
	})
	if err != nil {
		t.Fatalf("First setup failed: %v", err)
	}

	_, err = authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin2",
		AuthKey:  dbtest.AuthKey("anotherpass"), SaltSecret: dbtest.SaltSecret,
	})
	if err == nil {
		t.Error("Expected error on second setup attempt")
	}
}

func TestSetup_EmptyUsername(t *testing.T) {
	database := newTestDB(t)
	_, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "",
		AuthKey:  dbtest.AuthKey("validpassword"), SaltSecret: dbtest.SaltSecret,
	})
	if err == nil {
		t.Error("Expected error for empty username")
	}
}

func TestLogin_Success(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	_, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret,
	})
	if err != nil {
		t.Fatalf("Setup failed: %v", err)
	}

	result, err := authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"),
	})
	if err != nil {
		t.Fatalf("Login failed: %v", err)
	}
	if result.SessionToken == "" {
		t.Error("Expected non-empty session token")
	}
}

func TestLogin_WrongPassword(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	_, _ = authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret,
	})

	_, err := authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "admin",
		AuthKey:  dbtest.AuthKey("wrongpassword"),
	})
	if err == nil {
		t.Error("Expected error for wrong password")
	}
}

func TestLogin_WrongUsername(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	_, _ = authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret,
	})

	_, err := authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "notadmin",
		AuthKey:  dbtest.AuthKey("mypassword"),
	})
	if err == nil {
		t.Error("Expected error for wrong username")
	}
	// Error message should not reveal whether username exists
	if err.Error() != "invalid credentials" {
		t.Errorf("Expected 'invalid credentials', got %q", err.Error())
	}
}

func TestValidateSession_Valid(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	setupResult, _ := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret,
	})

	username, _, err := authutil.ValidateSession(context.Background(), queries, setupResult.SessionToken)
	if err != nil {
		t.Fatalf("ValidateSession failed: %v", err)
	}
	if username != "admin" {
		t.Errorf("Expected username 'admin', got %q", username)
	}
}

func TestValidateSession_Invalid(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	_, _, err := authutil.ValidateSession(context.Background(), queries, "notavalidtoken")
	if err == nil {
		t.Error("Expected error for invalid session token")
	}
}

func TestLogout_InvalidatesSession(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	setupResult, _ := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret,
	})

	err := authutil.Logout(context.Background(), queries, setupResult.SessionToken)
	if err != nil {
		t.Fatalf("Logout failed: %v", err)
	}

	_, _, err = authutil.ValidateSession(context.Background(), queries, setupResult.SessionToken)
	if err == nil {
		t.Error("Expected session to be invalid after logout")
	}
}

func TestRecover_Success(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	setupResult, _ := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username:    "admin",
		AuthKey:     dbtest.AuthKey("originalpass"),
		RecoveryKey: dbtest.AuthKey("admin-phrase"),
		SaltSecret:  dbtest.SaltSecret,
	})

	result, err := authutil.Recover(context.Background(), database, authutil.RecoverParams{
		Username:    "admin",
		RecoveryKey: dbtest.AuthKey("admin-phrase"),
		NewAuthKey:  dbtest.AuthKey("newpassword123"),
		SaltSecret:  dbtest.SaltSecret,
	})
	if err != nil {
		t.Fatalf("Recover failed: %v", err)
	}
	if result.SessionToken == "" {
		t.Error("Expected new session token after recovery")
	}

	// Old session should be invalidated
	_, _, err = authutil.ValidateSession(context.Background(), queries, setupResult.SessionToken)
	if err == nil {
		t.Error("Expected old session to be invalidated after recovery")
	}

	// Should be able to login with new password
	_, err = authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "admin",
		AuthKey:  dbtest.AuthKey("newpassword123"),
	})
	if err != nil {
		t.Errorf("Expected login with new password to work: %v", err)
	}

	// Old password should not work
	_, err = authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "admin",
		AuthKey:  dbtest.AuthKey("originalpass"),
	})
	if err == nil {
		t.Error("Expected old password to be rejected after recovery")
	}
}

func TestRecover_WrongPhrase(t *testing.T) {
	database := newTestDB(t)
	_, _ = authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username:    "admin",
		AuthKey:     dbtest.AuthKey("mypassword"),
		RecoveryKey: dbtest.AuthKey("admin-phrase"),
		SaltSecret:  dbtest.SaltSecret,
	})

	_, err := authutil.Recover(context.Background(), database, authutil.RecoverParams{
		Username:    "admin",
		RecoveryKey: dbtest.AuthKey("wrong-phrase"),
		NewAuthKey:  dbtest.AuthKey("newpassword123"),
		SaltSecret:  dbtest.SaltSecret,
	})
	if err == nil {
		t.Error("Expected error for wrong recovery phrase")
	}
}

// createUserWithKeys adds a second account the way Setup stores the first.
func createUserWithKeys(t *testing.T, queries *db.Queries, username, password, phrase string) {
	t.Helper()
	keyHash, err := authutil.HashKey(dbtest.AuthKey(password))
	if err != nil {
		t.Fatal(err)
	}
	recoveryHash, err := authutil.HashKey(dbtest.AuthKey(phrase))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := queries.CreateUser(context.Background(), db.CreateUserParams{
		Username:        username,
		AuthKeyHash:     keyHash,
		AuthSalt:        "AAAAAAAAAAAAAAAAAAAAAA==",
		RecoveryKeyHash: recoveryHash,
	}); err != nil {
		t.Fatal(err)
	}
}

// TestRecover_NamedAccount recovers the account the request names, not the
// founding one: a second user's key resets the second user's password.
func TestRecover_NamedAccount(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	ctx := context.Background()
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin",
		AuthKey: dbtest.AuthKey("admin-password"), RecoveryKey: dbtest.AuthKey("admin-phrase"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	createUserWithKeys(t, queries, "bob", "bob-password", "bob-phrase")

	if _, err := authutil.Recover(ctx, database, authutil.RecoverParams{
		Username:    "bob",
		RecoveryKey: dbtest.AuthKey("bob-phrase"),
		NewAuthKey:  dbtest.AuthKey("bob-new-password"),
		SaltSecret:  dbtest.SaltSecret,
	}); err != nil {
		t.Fatalf("Recover(bob, bob's key) failed: %v", err)
	}
	if _, err := authutil.Login(ctx, queries, authutil.LoginParams{Username: "bob", AuthKey: dbtest.AuthKey("bob-new-password")}); err != nil {
		t.Errorf("bob should log in with the new password: %v", err)
	}
	if _, err := authutil.Login(ctx, queries, authutil.LoginParams{Username: "admin", AuthKey: dbtest.AuthKey("admin-password")}); err != nil {
		t.Errorf("admin's password must be untouched: %v", err)
	}

	// The founder's key does not recover bob.
	if _, err := authutil.Recover(ctx, database, authutil.RecoverParams{
		Username:    "bob",
		RecoveryKey: dbtest.AuthKey("admin-phrase"),
		NewAuthKey:  dbtest.AuthKey("hijacked123"),
		SaltSecret:  dbtest.SaltSecret,
	}); err == nil {
		t.Error("Recover(bob, admin's key) should fail")
	}
}

// TestRecover_UnknownUserLooksLikeWrongPhrase keeps the endpoint from
// revealing which usernames exist.
func TestRecover_UnknownUserLooksLikeWrongPhrase(t *testing.T) {
	database := newTestDB(t)
	ctx := context.Background()
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin",
		AuthKey: dbtest.AuthKey("admin-password"), RecoveryKey: dbtest.AuthKey("admin-phrase"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}

	_, unknownErr := authutil.Recover(ctx, database, authutil.RecoverParams{
		Username:    "nobody",
		RecoveryKey: dbtest.AuthKey("admin-phrase"),
		NewAuthKey:  dbtest.AuthKey("newpassword123"),
		SaltSecret:  dbtest.SaltSecret,
	})
	_, wrongErr := authutil.Recover(ctx, database, authutil.RecoverParams{
		Username:    "admin",
		RecoveryKey: dbtest.AuthKey("wrong-phrase"),
		NewAuthKey:  dbtest.AuthKey("newpassword123"),
		SaltSecret:  dbtest.SaltSecret,
	})
	if unknownErr == nil || wrongErr == nil {
		t.Fatalf("expected both to fail, got unknown=%v wrong=%v", unknownErr, wrongErr)
	}
	if unknownErr.Error() != wrongErr.Error() {
		t.Errorf("unknown user error %q differs from wrong phrase error %q", unknownErr, wrongErr)
	}
}

func TestValidateBasicAuth_Success(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	_, _ = authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret,
	})

	username, _, err := authutil.ValidateBasicAuth(context.Background(), queries, "admin", dbtest.AuthKey("mypassword"))
	if err != nil {
		t.Fatalf("ValidateBasicAuth failed: %v", err)
	}
	if username != "admin" {
		t.Errorf("Expected username 'admin', got %q", username)
	}
}

func TestValidateBasicAuth_WrongPassword(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	_, _ = authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret,
	})

	_, _, err := authutil.ValidateBasicAuth(context.Background(), queries, "admin", dbtest.AuthKey("wrongpassword"))
	if err == nil {
		t.Error("Expected error for wrong password")
	}
}

func TestValidateBasicAuth_WrongUsername(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	_, _ = authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "admin",
		AuthKey:  dbtest.AuthKey("mypassword"), SaltSecret: dbtest.SaltSecret,
	})

	_, _, err := authutil.ValidateBasicAuth(context.Background(), queries, "notadmin", dbtest.AuthKey("mypassword"))
	if err == nil {
		t.Error("Expected error for wrong username")
	}
}
