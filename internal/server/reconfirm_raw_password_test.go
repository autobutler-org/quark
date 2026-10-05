package server

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// TestReconfirm_RawPasswordIsUpdateTheApp sends the raw password, as an app
// from before auth keys does, to every endpoint that re-confirms the caller in
// a password field, and as HTTP Basic. Each answers 426 with the
// update-the-app sentence rather than the 401 or 403 of a wrong password,
// which an old app would read as a typo (#2430). The auth key still passes
// where nothing else stands in the way.
func TestReconfirm_RawPasswordIsUpdateTheApp(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	t.Cleanup(func() { settingsutil.ResetForTesting("") })
	ctx := context.Background()

	database := dbtest.NewDB(t)
	setup, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret})
	if err != nil {
		t.Fatalf("authutil.Setup: %v", err)
	}
	session := vaultcrypto.NewVaultSession()
	if _, err := vaultutil.Setup(ctx, vaultutil.SetupParams{Queries: database.Queries, Session: session, MasterPassword: "vault-master-password"}); err != nil {
		t.Fatalf("vaultutil.Setup: %v", err)
	}
	deps := deputil.NewDependencies().WithDatabase(database).WithVaultSession(session)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	middleware.Use(engine, deps)
	setupRouters(engine, nil, deps)

	send := func(method, path string, body any) *httptest.ResponseRecorder {
		t.Helper()
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		req := httptest.NewRequest(method, path, bytes.NewReader(encoded))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+setup.SessionToken)
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		return w
	}
	const raw = "admin-password"
	for _, tc := range []struct {
		method, path string
		body         any
	}{
		{http.MethodDelete, "/api/v0/auth/account?account=true", map[string]string{"password": raw}},
		{http.MethodPut, "/api/v0/auth/recovery-key", map[string]string{"password": raw, "recoveryKey": dbtest.AuthKey("phrase")}},
		{http.MethodPut, "/api/v0/vault/storage-location", map[string]string{"targetDeviceSerial": "", "username": "admin", "password": raw}},
		{http.MethodPut, "/api/v0/storage/devices/role", map[string]string{"serial": "", "role": "unassigned", "username": "admin", "password": raw}},
	} {
		w := send(tc.method, tc.path, tc.body)
		if w.Code != http.StatusUpgradeRequired || errorOf(t, w) != authutil.ErrAppTooOld.Error() {
			t.Errorf("%s %s with the raw password = %d %s, want 426 with the update-the-app copy", tc.method, tc.path, w.Code, w.Body)
		}
	}

	if w := send(http.MethodPut, "/api/v0/auth/recovery-key", map[string]string{"password": dbtest.AuthKey(raw), "recoveryKey": dbtest.AuthKey("phrase")}); w.Code != http.StatusNoContent {
		t.Errorf("recovery key with the auth key = %d %s, want 204", w.Code, w.Body)
	}

	basic := func(password string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, "/api/v0/vault/status", nil)
		req.SetBasicAuth("admin", password)
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		return w
	}
	if w := basic(raw); w.Code != http.StatusUpgradeRequired || errorOf(t, w) != authutil.ErrAppTooOld.Error() {
		t.Errorf("Basic with the raw password = %d %s, want 426 with the update-the-app copy", w.Code, w.Body)
	}
	if w := basic(dbtest.AuthKey(raw)); w.Code != http.StatusOK {
		t.Errorf("Basic with the auth key = %d %s, want 200", w.Code, w.Body)
	}
}

// errorOf is the error field of w's JSON body.
func errorOf(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var body struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("body %q is not JSON: %v", w.Body, err)
	}
	return body.Error
}
