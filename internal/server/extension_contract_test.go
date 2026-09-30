package server

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// TestExtensionContract pins the request and response shapes the browser
// extension (autobutler-org/quark-browser-extensions, src/shared/api.ts) depends on.
// That client lives in another repository, so nothing else here would notice
// a renamed field or a changed status code. A change that breaks this test
// needs a matching change in the extension.
func TestExtensionContract(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	ctx := context.Background()

	database := dbtest.NewDB(t)
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", Password: "admin-password"}); err != nil {
		t.Fatalf("authutil.Setup: %v", err)
	}
	hash, err := authutil.HashPassword("pending-password")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "pending", PasswordHash: hash, RecoveryPhraseHash: hash}); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{ToStatus: authutil.StatusPending, Username: "pending", FromStatus: authutil.StatusActive}); err != nil {
		t.Fatal(err)
	}

	session := vaultcrypto.NewVaultSession()
	if _, err := vaultutil.Setup(ctx, vaultutil.SetupParams{Queries: database.Queries, Session: session, MasterPassword: "vault-master-password"}); err != nil {
		t.Fatalf("vaultutil.Setup: %v", err)
	}
	key, ok := session.Key()
	if !ok {
		t.Fatal("vault not unlocked after setup")
	}
	created, err := vaultutil.CreateEntry(ctx, vaultutil.CreateEntryParams{
		Queries: database.Queries,
		Key:     key,
		Fields:  vaultutil.EntryFields{Name: "GitHub", URL: "https://github.com/login", Username: "alice", Password: "gh-pass", TOTPSecret: "JBSWY3DPEHPK3PXP"},
	})
	vaultcrypto.ZeroKey(key)
	if err != nil {
		t.Fatal(err)
	}
	entryPath := "/api/v0/vault/entries/" + jsonNumber(created.Entry.ID)

	deps := deputil.NewDependencies().WithDatabase(database).WithVaultSession(session)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	middleware.Use(engine, deps)
	setupRouters(engine, nil, deps)

	do := func(method, path, token string, body any) (int, map[string]any) {
		t.Helper()
		var reader io.Reader
		if body != nil {
			encoded, err := json.Marshal(body)
			if err != nil {
				t.Fatal(err)
			}
			reader = bytes.NewReader(encoded)
		}
		req := httptest.NewRequest(method, path, reader)
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		decoded := map[string]any{}
		if w.Body.Len() > 0 {
			if err := json.Unmarshal(w.Body.Bytes(), &decoded); err != nil {
				t.Fatalf("%s %s: body is not a JSON object: %s", method, path, w.Body.String())
			}
		}
		return w.Code, decoded
	}

	code, body := do(http.MethodPost, "/api/v0/auth/login", "", map[string]string{"username": "admin", "password": "admin-password"})
	expectStatus(t, "login", code, http.StatusOK)
	token := expectString(t, "login token", body, "token")

	code, _ = do(http.MethodPost, "/api/v0/auth/login", "", map[string]string{"username": "admin", "password": "wrong"})
	expectStatus(t, "login with a wrong password", code, http.StatusUnauthorized)

	code, body = do(http.MethodPost, "/api/v0/auth/login", "", map[string]string{"username": "pending", "password": "pending-password"})
	expectStatus(t, "login to a pending account", code, http.StatusForbidden)
	if status := expectString(t, "refusal status", body, "status"); status != authutil.StatusPending {
		t.Errorf("refusal status = %q, want %q", status, authutil.StatusPending)
	}
	expectString(t, "refusal error", body, "error")

	code, body = do(http.MethodGet, "/api/v0/vault/status", "", nil)
	expectStatus(t, "vault status without a token", code, http.StatusUnauthorized)
	if msg := expectString(t, "missing-token error", body, "error"); msg != "authentication required" {
		t.Errorf("missing-token error = %q; the extension tells an expired session from a wrong vault password by this text", msg)
	}

	code, body = do(http.MethodGet, "/api/v0/vault/status", token, nil)
	expectStatus(t, "vault status", code, http.StatusOK)
	expectBool(t, "status.initialized", body, "initialized")
	expectBool(t, "status.locked", body, "locked")
	expectBool(t, "status.deviceConnected", body, "deviceConnected")
	expectNumber(t, "status.autoLockSeconds", body, "autoLockSeconds")

	code, body = do(http.MethodGet, "/api/v0/vault/entries", token, nil)
	expectStatus(t, "list entries", code, http.StatusOK)
	expectEntryList(t, body)

	code, body = do(http.MethodGet, entryPath, token, nil)
	expectStatus(t, "get entry", code, http.StatusOK)
	expectNumber(t, "entry.id", body, "id")
	for _, field := range []string{"name", "url", "urlHost", "username", "password", "totpSecret"} {
		expectString(t, "entry."+field, body, field)
	}

	code, body = do(http.MethodGet, "/api/v0/vault/entries/999999", token, nil)
	expectStatus(t, "get a missing entry", code, http.StatusNotFound)
	expectString(t, "missing entry error", body, "error")

	code, body = do(http.MethodPost, "/api/v0/vault/generate", token, map[string]any{"length": 16, "uppercase": true, "lowercase": true, "digits": true, "symbols": true, "avoidAmbiguous": true})
	expectStatus(t, "generate", code, http.StatusOK)
	if password := expectString(t, "generated password", body, "password"); len(password) != 16 {
		t.Errorf("generated %d characters, want the requested 16", len(password))
	}

	code, body = do(http.MethodPost, "/api/v0/vault/entries", token, map[string]string{"name": "example.com", "url": "https://example.com", "username": "bob", "password": "pw"})
	expectStatus(t, "create entry", code, http.StatusOK)
	expectNumber(t, "created entry id", body, "id")

	code, body = do(http.MethodPut, entryPath, token, map[string]any{
		"name": "GitHub", "url": "https://github.com/login", "username": "alice", "password": "new-pass",
		"notes": "", "totpSecret": "JBSWY3DPEHPK3PXP", "customFields": []any{}, "folderId": nil,
	})
	expectStatus(t, "replace entry", code, http.StatusOK)
	expectNumber(t, "replaced entry id", body, "id")

	code, _ = do(http.MethodPost, "/api/v0/vault/lock", token, nil)
	expectStatus(t, "lock", code, http.StatusOK)

	code, body = do(http.MethodGet, entryPath, token, nil)
	expectStatus(t, "get entry while locked", code, 423)
	if msg := expectString(t, "locked error", body, "error"); !strings.HasPrefix(msg, "vault is locked") {
		t.Errorf("locked error = %q; the extension strips a leading \"vault is locked\" to show the reason", msg)
	}

	code, body = do(http.MethodGet, "/api/v0/vault/entries", token, nil)
	expectStatus(t, "list entries while locked", code, http.StatusOK)
	expectEntryList(t, body)

	code, body = do(http.MethodPost, "/api/v0/vault/unlock", token, map[string]string{"masterPassword": "wrong"})
	expectStatus(t, "unlock with a wrong password", code, http.StatusUnauthorized)
	if msg := expectString(t, "wrong-password error", body, "error"); msg == "authentication required" {
		t.Error("a wrong vault password must not read like a missing session")
	}

	code, body = do(http.MethodPost, "/api/v0/vault/unlock", token, map[string]string{"masterPassword": "vault-master-password"})
	expectStatus(t, "unlock", code, http.StatusOK)
	expectBool(t, "unlock.locked", body, "locked")

	preflight := httptest.NewRequest(http.MethodOptions, "/api/v0/vault/entries", nil)
	preflight.Header.Set("Origin", "chrome-extension://abcdefghijklmnop")
	preflight.Header.Set("Access-Control-Request-Method", http.MethodGet)
	preflight.Header.Set("Access-Control-Request-Headers", "authorization,content-type")
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, preflight)
	if w.Code != http.StatusNoContent && w.Code != http.StatusOK {
		t.Errorf("CORS preflight = %d, want 204", w.Code)
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("Access-Control-Allow-Origin = %q, want *", got)
	}
	if !strings.Contains(strings.ToLower(w.Header().Get("Access-Control-Allow-Headers")), "authorization") {
		t.Errorf("Access-Control-Allow-Headers = %q, want Authorization allowed", w.Header().Get("Access-Control-Allow-Headers"))
	}
	if w.Header().Get("Access-Control-Allow-Credentials") == "true" {
		t.Error("CORS must not allow credentials; the extension sends a bearer token, never cookies")
	}

	code, _ = do(http.MethodPost, "/api/v0/auth/logout", token, nil)
	expectStatus(t, "logout", code, http.StatusOK)
	code, _ = do(http.MethodGet, "/api/v0/vault/status", token, nil)
	expectStatus(t, "vault status after logout", code, http.StatusUnauthorized)
}

func jsonNumber(id int64) string {
	encoded, _ := json.Marshal(id)
	return string(encoded)
}

func expectStatus(t *testing.T, what string, got, want int) {
	t.Helper()
	if got != want {
		t.Fatalf("%s: status %d, want %d", what, got, want)
	}
}

func expectString(t *testing.T, what string, body map[string]any, key string) string {
	t.Helper()
	value, ok := body[key].(string)
	if !ok {
		t.Errorf("%s: %q is %T, want a string", what, key, body[key])
	}
	return value
}

func expectBool(t *testing.T, what string, body map[string]any, key string) {
	t.Helper()
	if _, ok := body[key].(bool); !ok {
		t.Errorf("%s: %q is %T, want a bool", what, key, body[key])
	}
}

func expectNumber(t *testing.T, what string, body map[string]any, key string) {
	t.Helper()
	if _, ok := body[key].(float64); !ok {
		t.Errorf("%s: %q is %T, want a number", what, key, body[key])
	}
}

func expectEntryList(t *testing.T, body map[string]any) {
	t.Helper()
	entries, ok := body["entries"].([]any)
	if !ok || len(entries) == 0 {
		t.Fatalf("entries is %T with %d items, want a non-empty array", body["entries"], len(entries))
	}
	for _, raw := range entries {
		entry, ok := raw.(map[string]any)
		if !ok {
			t.Fatalf("entry is %T, want an object", raw)
		}
		expectNumber(t, "list entry id", entry, "id")
		for _, field := range []string{"name", "urlHost", "createdAt", "updatedAt"} {
			expectString(t, "list entry "+field, entry, field)
		}
		if folder, present := entry["folderId"]; !present {
			t.Error("list entry has no folderId key; the extension expects null or a number")
		} else if _, isNumber := folder.(float64); folder != nil && !isNumber {
			t.Errorf("list entry folderId is %T, want null or a number", folder)
		}
		if _, leaked := entry["password"]; leaked {
			t.Error("the entry list must not carry passwords")
		}
	}
}
