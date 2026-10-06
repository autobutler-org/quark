package v0_auth_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// newPublicAuthEngine mounts the auth router the way requireAuth leaves its
// exempt routes: dependencies on the context and no caller. The salt secret
// lives in a temporary settings file.
func newPublicAuthEngine(t *testing.T, database *db.DatabaseSqlc) *gin.Engine {
	t.Helper()
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	t.Cleanup(func() { settingsutil.ResetForTesting("") })
	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_auth.NewRouter())
	return engine
}

func postJSON(engine *gin.Engine, path string, body any) *httptest.ResponseRecorder {
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

func getPath(engine *gin.Engine, path string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	return w
}

func decodeBody(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode %q: %v", w.Body.String(), err)
	}
	return body
}

func setUserStatus(t *testing.T, queries *db.Queries, username, from, to string) {
	t.Helper()
	if _, err := queries.SetUserStatus(context.Background(), db.SetUserStatusParams{Username: username, FromStatus: from, ToStatus: to}); err != nil {
		t.Fatal(err)
	}
}

// TestLoginUser_StatusRefusals drives POST /auth/login for each account status.
// The right password on a pending or disabled account is 403 with a status the
// app reads; a wrong password is the same 401 whatever the status. The
// founding admin signs in exactly as before.
func TestLoginUser_StatusRefusals(t *testing.T) {
	database := dbtest.NewDB(t)
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	createRecoverableUser(t, database.Queries, "waiting", "apple-bread-cloud-delta-eagle-flame")
	setUserStatus(t, database.Queries, "waiting", authutil.StatusActive, authutil.StatusPending)
	createRecoverableUser(t, database.Queries, "off", "apple-bread-cloud-delta-eagle-flame")
	setUserStatus(t, database.Queries, "off", authutil.StatusActive, authutil.StatusDisabled)
	engine := newPublicAuthEngine(t, database)

	founder := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "authKey": dbtest.AuthKey("admin-password")})
	if founder.Code != http.StatusOK || decodeBody(t, founder)["token"] == "" {
		t.Errorf("founder login = %d: %s", founder.Code, founder.Body.String())
	}

	for _, tc := range []struct{ user, status, text string }{
		{"waiting", authutil.StatusPending, authutil.ErrAccountPending.Error()},
		{"off", authutil.StatusDisabled, authutil.ErrAccountDisabled.Error()},
	} {
		right := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": tc.user, "authKey": dbtest.AuthKey("original-password")})
		if right.Code != http.StatusForbidden {
			t.Errorf("%s right password = %d, want 403: %s", tc.user, right.Code, right.Body.String())
			continue
		}
		body := decodeBody(t, right)
		if body["status"] != tc.status || body["error"] != tc.text {
			t.Errorf("%s body = %v, want status %q error %q", tc.user, body, tc.status, tc.text)
		}
		if _, ok := body["token"]; ok {
			t.Errorf("%s refused login carried a token", tc.user)
		}

		wrong := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": tc.user, "authKey": dbtest.AuthKey("not-it")})
		stranger := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "nobody", "authKey": dbtest.AuthKey("not-it")})
		if wrong.Code != http.StatusUnauthorized || wrong.Body.String() != stranger.Body.String() {
			t.Errorf("%s wrong password = %d %s, want the stranger's 401 %s", tc.user, wrong.Code, wrong.Body.String(), stranger.Body.String())
		}
	}
}

// TestRecoverAccount_StatusRefusal checks the right phrase for a pending
// account is 403 with its status, the same shape login uses.
func TestRecoverAccount_StatusRefusal(t *testing.T) {
	database := dbtest.NewDB(t)
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	const phrase = "apple-bread-cloud-delta-eagle-flame"
	createRecoverableUser(t, database.Queries, "waiting", phrase)
	setUserStatus(t, database.Queries, "waiting", authutil.StatusActive, authutil.StatusPending)
	engine := newPublicAuthEngine(t, database)

	w := postJSON(engine, "/api/v0/auth/recover", map[string]string{"username": "waiting", "recoveryKey": dbtest.AuthKey(phrase), "newAuthKey": dbtest.AuthKey("brand-new-password")})
	if w.Code != http.StatusForbidden {
		t.Fatalf("recover pending = %d, want 403: %s", w.Code, w.Body.String())
	}
	if body := decodeBody(t, w); body["status"] != authutil.StatusPending {
		t.Errorf("recover pending body = %v, want status pending", body)
	}
}

// TestAuthRoutes_LookupErrorIs503 is #2858 on the two routes requireAuth lets
// through unchecked: a sign-in whose account could not be looked up is a 503,
// not the 401 of a wrong password, and a status call whose session could not
// be looked up is a 503, not an anonymous 200. Both answer as before once the
// database does.
func TestAuthRoutes_LookupErrorIs503(t *testing.T) {
	database := dbtest.NewDB(t)
	setup, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret})
	if err != nil {
		t.Fatal(err)
	}
	engine := newPublicAuthEngine(t, database)
	login := func() *httptest.ResponseRecorder {
		return postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "admin", "authKey": dbtest.AuthKey("admin-password")})
	}
	status := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, "/api/v0/auth/status", nil)
		req.Header.Set("Authorization", "Bearer "+setup.SessionToken)
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		return w
	}
	expectUnavailable := func(name string, w *httptest.ResponseRecorder) {
		t.Helper()
		if w.Code != http.StatusServiceUnavailable || decodeBody(t, w)["error"] != authutil.ErrUnavailable.Error() {
			t.Errorf("%s = %d %s, want 503 service unavailable", name, w.Code, w.Body)
		}
	}

	restore := dbtest.HideTable(t, database.Db, "users")
	expectUnavailable("login, failed lookup", login())
	restore()
	if w := login(); w.Code != http.StatusOK {
		t.Errorf("login once the database answers = %d, want 200: %s", w.Code, w.Body)
	}

	restore = dbtest.HideTable(t, database.Db, "sessions")
	expectUnavailable("status, failed lookup", status())
	restore()
	if w := status(); w.Code != http.StatusOK || decodeBody(t, w)["username"] != "admin" {
		t.Errorf("status once the database answers = %d %s, want 200 for admin", w.Code, w.Body)
	}
}
