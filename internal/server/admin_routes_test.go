package server

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/gin-gonic/gin"
)

// TestAdminGate_ApplianceRoutes mounts the real middleware and routers with
// two accounts: the founding admin and a member. Every route that changes the
// appliance for everyone refuses the member with 403 and lets the admin
// through, while the read-only routes and account-only deletion stay open.
func TestAdminGate_ApplianceRoutes(t *testing.T) {
	// Handlers the admin reaches resolve the data directory from HOME.
	t.Setenv("HOME", t.TempDir())

	database := dbtest.NewDB(t)
	ctx := context.Background()
	admin, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", Password: "admin-password"})
	if err != nil {
		t.Fatalf("authutil.Setup: %v", err)
	}
	hash, err := authutil.HashPassword("member-password")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "member", PasswordHash: hash, RecoveryPhraseHash: hash}); err != nil {
		t.Fatalf("create member: %v", err)
	}
	member, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "member", Password: "member-password"})
	if err != nil {
		t.Fatalf("login member: %v", err)
	}

	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	// The graph carries only a database, so a handler the admin reaches may
	// panic on a missing dependency. That still proves it got past the gate.
	engine.Use(gin.CustomRecoveryWithWriter(io.Discard, func(c *gin.Context, _ any) {
		c.AbortWithStatus(http.StatusInternalServerError)
	}))
	middleware.Use(engine, deps)
	setupRouters(engine, nil, deps)

	do := func(method, path, token string) int {
		req := httptest.NewRequest(method, path, nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		return w.Code
	}

	gated := []struct{ method, path string }{
		{http.MethodPost, "/api/v0/storage/devices/usb/serial-1"},
		{http.MethodDelete, "/api/v0/storage/devices/usb/serial-1"},
		{http.MethodPut, "/api/v0/storage/devices/role"},
		{http.MethodPatch, "/api/v0/storage/devices/rename"},
		{http.MethodPost, "/api/v0/storage/devices/snapshot-backup"},
		{http.MethodPost, "/api/v0/storage/devices/snapshot-backup/verify"},
		{http.MethodDelete, "/api/v0/devices/1"},
		{http.MethodPost, "/api/v0/version/update"},
		{http.MethodPost, "/api/v0/settings"},
		// No body, so the admin stops at a 400 and the setting is untouched.
		{http.MethodPut, "/api/v0/settings/access-requests"},
		// No body, so the admin stops at a 400 and no account is created.
		{http.MethodPost, "/api/v0/admin/users"},
		// Nobody has requested an account, so the admin gets a 404.
		{http.MethodPut, "/api/v0/admin/approve/nobody"},
		{http.MethodPut, "/api/v0/admin/deny/nobody"},
		// No account has that name, so the admin gets a 404.
		{http.MethodPut, "/api/v0/admin/disable/nobody"},
		{http.MethodPut, "/api/v0/admin/enable/nobody"},
		{http.MethodDelete, "/api/v0/admin/users/nobody"},
		{http.MethodGet, "/api/v0/admin/groups"},
		// No body, so the admin stops at a 400 and no group is created.
		{http.MethodPost, "/api/v0/admin/groups"},
		// No group has that id, so the admin gets a 404.
		{http.MethodPut, "/api/v0/admin/groups/999"},
		{http.MethodDelete, "/api/v0/admin/groups/999"},
		// confirm names neither account, so the admin stops at a 400 after the
		// gate and nothing is deleted.
		{http.MethodDelete, "/api/v0/auth/account?database=true&confirm=nobody"},
		{http.MethodDelete, "/api/v0/auth/account?files=true&confirm=nobody"},
		{http.MethodDelete, "/api/v0/auth/account?devices=true&confirm=nobody"},
		{http.MethodGet, "/api/v0/vault/status"},
		{http.MethodPost, "/api/v0/vault/setup"},
		{http.MethodPost, "/api/v0/vault/unlock"},
		{http.MethodPost, "/api/v0/vault/lock"},
		{http.MethodGet, "/api/v0/vault/entries"},
		{http.MethodGet, "/api/v0/vault/entries/1"},
		{http.MethodPost, "/api/v0/vault/entries"},
		{http.MethodPut, "/api/v0/vault/entries/1"},
		{http.MethodDelete, "/api/v0/vault/entries/1"},
		{http.MethodGet, "/api/v0/vault/folders"},
		{http.MethodPost, "/api/v0/vault/folders"},
		{http.MethodPut, "/api/v0/vault/folders/1"},
		{http.MethodDelete, "/api/v0/vault/folders/1"},
		{http.MethodPost, "/api/v0/vault/generate"},
		{http.MethodPut, "/api/v0/vault/change-password"},
		{http.MethodPost, "/api/v0/vault/import-backup"},
		{http.MethodPost, "/api/v0/vault/import"},
		{http.MethodGet, "/api/v0/vault/export"},
		{http.MethodGet, "/api/v0/vault/storage-location"},
		{http.MethodPut, "/api/v0/vault/storage-location"},
	}
	for _, r := range gated {
		if got := do(r.method, r.path, member.SessionToken); got != http.StatusForbidden {
			t.Errorf("member %s %s = %d, want 403", r.method, r.path, got)
		}
		// The member's 403 already proves the route is mounted behind the gate:
		// gin runs group middleware only for a matched route. Past the gate a
		// handler may answer anything, including 404 for a drive that is not
		// attached, so only 401 and 403 mean the admin was refused.
		if got := do(r.method, r.path, admin.SessionToken); got == http.StatusUnauthorized || got == http.StatusForbidden {
			t.Errorf("admin %s %s = %d, want it past the gate", r.method, r.path, got)
		}
	}

	open := []struct{ method, path string }{
		{http.MethodGet, "/api/v0/settings"},
		{http.MethodGet, "/api/v0/version"},
		{http.MethodGet, "/api/v0/version/available"},
		{http.MethodGet, "/api/v0/devices"},
		{http.MethodGet, "/api/v0/storage/devices/status"},
		// Account-only deletion stays self-service; the wrong confirm keeps the
		// member's account in place.
		{http.MethodDelete, "/api/v0/auth/account?account=true&confirm=nobody"},
	}
	for _, r := range open {
		if got := do(r.method, r.path, member.SessionToken); got == http.StatusUnauthorized || got == http.StatusForbidden || got == http.StatusNotFound {
			t.Errorf("member %s %s = %d, want it open to every account", r.method, r.path, got)
		}
	}
}
