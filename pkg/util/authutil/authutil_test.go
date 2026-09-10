package authutil_test

import (
	"context"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// --- Unit tests ---

func TestHashPassword_AndCheck(t *testing.T) {
	hash, err := authutil.HashPassword("correct-horse-battery")
	if err != nil {
		t.Fatalf("HashPassword failed: %v", err)
	}
	if hash == "" {
		t.Error("Expected non-empty hash")
	}
	if !authutil.CheckPassword("correct-horse-battery", hash) {
		t.Error("CheckPassword should return true for correct password")
	}
	if authutil.CheckPassword("wrong-password", hash) {
		t.Error("CheckPassword should return false for wrong password")
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

func TestGenerateRecoveryPhrase(t *testing.T) {
	phrase, err := authutil.GenerateRecoveryPhrase()
	if err != nil {
		t.Fatalf("GenerateRecoveryPhrase failed: %v", err)
	}
	words := strings.Split(phrase, "-")
	if len(words) != 6 {
		t.Errorf("Expected 6 words, got %d: %q", len(words), phrase)
	}
	for _, w := range words {
		if w == "" {
			t.Error("Expected non-empty words in recovery phrase")
		}
	}
	// Should be unique (probabilistically)
	phrase2, _ := authutil.GenerateRecoveryPhrase()
	if phrase == phrase2 {
		t.Error("Expected unique recovery phrases")
	}
}

func TestNormalizeRecoveryPhrase(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"Hello-World-Test", "hello-world-test"},
		{"  hello-world  ", "hello-world"},
		{"UPPER-CASE", "upper-case"},
	}
	for _, tt := range tests {
		got := authutil.NormalizeRecoveryPhrase(tt.input)
		if got != tt.want {
			t.Errorf("NormalizeRecoveryPhrase(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

// --- Integration tests (real SQLite, full flow) ---

func TestIsSetupComplete_FreshDB(t *testing.T) {
	queries := newTestDB(t)
	complete, err := authutil.IsSetupComplete(context.Background(), queries)
	if err != nil {
		t.Fatalf("IsSetupComplete failed: %v", err)
	}
	if complete {
		t.Error("Expected setup not complete on fresh DB")
	}
}

func TestSetup_Success(t *testing.T) {
	queries := newTestDB(t)
	result, err := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "supersecret",
	})
	if err != nil {
		t.Fatalf("Setup failed: %v", err)
	}
	if result.SessionToken == "" {
		t.Error("Expected non-empty session token")
	}
	if result.RecoveryPhrase == "" {
		t.Error("Expected non-empty recovery phrase")
	}
	// Recovery phrase should be 6 words
	words := strings.Split(result.RecoveryPhrase, "-")
	if len(words) != 6 {
		t.Errorf("Expected 6-word recovery phrase, got %d words", len(words))
	}

	// Setup should now be complete
	complete, _ := authutil.IsSetupComplete(context.Background(), queries)
	if !complete {
		t.Error("Expected setup to be complete after Setup()")
	}
}

func TestSetup_CannotRunTwice(t *testing.T) {
	queries := newTestDB(t)
	_, err := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "supersecret",
	})
	if err != nil {
		t.Fatalf("First setup failed: %v", err)
	}

	_, err = authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin2",
		Password: "anotherpass",
	})
	if err == nil {
		t.Error("Expected error on second setup attempt")
	}
}

func TestSetup_ShortPassword(t *testing.T) {
	queries := newTestDB(t)
	_, err := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "short",
	})
	if err == nil {
		t.Error("Expected error for password shorter than 8 chars")
	}
}

func TestSetup_EmptyUsername(t *testing.T) {
	queries := newTestDB(t)
	_, err := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "",
		Password: "validpassword",
	})
	if err == nil {
		t.Error("Expected error for empty username")
	}
}

func TestLogin_Success(t *testing.T) {
	queries := newTestDB(t)
	_, err := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
	})
	if err != nil {
		t.Fatalf("Setup failed: %v", err)
	}

	result, err := authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "admin",
		Password: "mypassword",
	})
	if err != nil {
		t.Fatalf("Login failed: %v", err)
	}
	if result.SessionToken == "" {
		t.Error("Expected non-empty session token")
	}
}

func TestLogin_WrongPassword(t *testing.T) {
	queries := newTestDB(t)
	_, _ = authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
	})

	_, err := authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "admin",
		Password: "wrongpassword",
	})
	if err == nil {
		t.Error("Expected error for wrong password")
	}
}

func TestLogin_WrongUsername(t *testing.T) {
	queries := newTestDB(t)
	_, _ = authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
	})

	_, err := authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "notadmin",
		Password: "mypassword",
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
	queries := newTestDB(t)
	setupResult, _ := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
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
	queries := newTestDB(t)
	_, _, err := authutil.ValidateSession(context.Background(), queries, "notavalidtoken")
	if err == nil {
		t.Error("Expected error for invalid session token")
	}
}

func TestLogout_InvalidatesSession(t *testing.T) {
	queries := newTestDB(t)
	setupResult, _ := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
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
	queries := newTestDB(t)
	setupResult, _ := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "originalpass",
	})

	result, err := authutil.Recover(context.Background(), queries, authutil.RecoverParams{
		RecoveryPhrase: setupResult.RecoveryPhrase,
		NewPassword:    "newpassword123",
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
		Password: "newpassword123",
	})
	if err != nil {
		t.Errorf("Expected login with new password to work: %v", err)
	}

	// Old password should not work
	_, err = authutil.Login(context.Background(), queries, authutil.LoginParams{
		Username: "admin",
		Password: "originalpass",
	})
	if err == nil {
		t.Error("Expected old password to be rejected after recovery")
	}
}

func TestRecover_WrongPhrase(t *testing.T) {
	queries := newTestDB(t)
	_, _ = authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
	})

	_, err := authutil.Recover(context.Background(), queries, authutil.RecoverParams{
		RecoveryPhrase: "wrong-phrase-that-does-not-match-anything",
		NewPassword:    "newpassword123",
	})
	if err == nil {
		t.Error("Expected error for wrong recovery phrase")
	}
}

func TestValidateBasicAuth_Success(t *testing.T) {
	queries := newTestDB(t)
	_, _ = authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
	})

	username, _, err := authutil.ValidateBasicAuth(context.Background(), queries, "admin", "mypassword")
	if err != nil {
		t.Fatalf("ValidateBasicAuth failed: %v", err)
	}
	if username != "admin" {
		t.Errorf("Expected username 'admin', got %q", username)
	}
}

func TestValidateBasicAuth_WrongPassword(t *testing.T) {
	queries := newTestDB(t)
	_, _ = authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
	})

	_, _, err := authutil.ValidateBasicAuth(context.Background(), queries, "admin", "wrongpassword")
	if err == nil {
		t.Error("Expected error for wrong password")
	}
}

func TestValidateBasicAuth_WrongUsername(t *testing.T) {
	queries := newTestDB(t)
	_, _ = authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
	})

	_, _, err := authutil.ValidateBasicAuth(context.Background(), queries, "notadmin", "mypassword")
	if err == nil {
		t.Error("Expected error for wrong username")
	}
}

func TestRecover_CaseInsensitive(t *testing.T) {
	queries := newTestDB(t)
	setupResult, _ := authutil.Setup(context.Background(), queries, authutil.SetupParams{
		Username: "admin",
		Password: "mypassword",
	})

	// Recovery phrase should work regardless of case
	upperPhrase := strings.ToUpper(setupResult.RecoveryPhrase)
	_, err := authutil.Recover(context.Background(), queries, authutil.RecoverParams{
		RecoveryPhrase: upperPhrase,
		NewPassword:    "newpassword123",
	})
	if err != nil {
		t.Errorf("Recovery should work with uppercased phrase: %v", err)
	}
}
