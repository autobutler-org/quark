package v0_auth_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// TestGetAuthStatus_ReportsCaller checks that GET /auth/status tells an
// authenticated caller who they are and whether they are an admin, and tells
// an anonymous caller nothing beyond whether setup is done.
func TestGetAuthStatus_ReportsCaller(t *testing.T) {
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	database := dbtest.NewDB(t)
	ctx := context.Background()
	founder, err := authutil.Setup(ctx, database.Queries, authutil.SetupParams{Username: "admin", Password: "admin-password"})
	if err != nil {
		t.Fatalf("authutil.Setup: %v", err)
	}
	createRecoverableUser(t, database.Queries, "bob", "apple-bread-cloud-delta-eagle-flame")
	bob, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "bob", Password: "original-password"})
	if err != nil {
		t.Fatalf("login bob: %v", err)
	}

	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_auth.NewRouter())

	status := func(t *testing.T, prepare func(*http.Request)) map[string]any {
		t.Helper()
		req := httptest.NewRequest(http.MethodGet, "/api/v0/auth/status", nil)
		prepare(req)
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("GET /auth/status = %d: %s", w.Code, w.Body.String())
		}
		var body map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		return body
	}
	bearer := func(token string) func(*http.Request) {
		return func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+token) }
	}

	cases := []struct {
		name    string
		prepare func(*http.Request)
		want    map[string]any
	}{
		{"anonymous", func(*http.Request) {}, map[string]any{"setup": true, "accessRequestsEnabled": true}},
		{"invalid token", bearer("not-a-session"), map[string]any{"setup": true, "accessRequestsEnabled": true}},
		{"admin", bearer(founder.SessionToken), map[string]any{"setup": true, "accessRequestsEnabled": true, "username": "admin", "isAdmin": true}},
		{"non-admin", bearer(bob.SessionToken), map[string]any{"setup": true, "accessRequestsEnabled": true, "username": "bob", "isAdmin": false}},
		{"session cookie", func(r *http.Request) {
			r.AddCookie(&http.Cookie{Name: "session", Value: bob.SessionToken})
		}, map[string]any{"setup": true, "accessRequestsEnabled": true, "username": "bob", "isAdmin": false}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := status(t, tc.prepare)
			if len(got) != len(tc.want) {
				t.Fatalf("body = %v, want %v", got, tc.want)
			}
			for k, v := range tc.want {
				if got[k] != v {
					t.Errorf("body[%q] = %v, want %v (body %v)", k, got[k], v, got)
				}
			}
		})
	}
}
