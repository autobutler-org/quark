package v0_admin_test

import (
	"context"
	"errors"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestDisableAndEnableUser_Endpoints drives PUT /admin/disable and
// /admin/enable: turning an account off ends its session and refuses its
// sign-in with the disabled status, turning it on restores sign-in, and each
// success publishes account_changed. The caller's own account is 400, and an
// account in the wrong status is 404.
func TestDisableAndEnableUser_Endpoints(t *testing.T) {
	h := newAdminHarness(t)
	ctx := context.Background()
	h.addUser(t, "member", authutil.StatusActive, false)
	session, err := authutil.Login(ctx, h.database.Queries, authutil.LoginParams{Username: "member", Password: "user-password"})
	if err != nil {
		t.Fatal(err)
	}

	if w := h.do(http.MethodPut, "/api/v0/admin/disable/member"); w.Code != http.StatusOK {
		t.Fatalf("disable = %d: %s", w.Code, w.Body.String())
	}
	if n := h.drainEvents(); n != 1 {
		t.Errorf("disable published %d account_changed events, want 1", n)
	}
	if _, _, err := authutil.ValidateSession(ctx, h.database.Queries, session.SessionToken); err == nil {
		t.Error("disabled account's session still validates")
	}
	if _, err := authutil.Login(ctx, h.database.Queries, authutil.LoginParams{Username: "member", Password: "user-password"}); !errors.Is(err, authutil.ErrAccountDisabled) {
		t.Errorf("login after disable = %v, want ErrAccountDisabled", err)
	}

	self := h.do(http.MethodPut, "/api/v0/admin/disable/admin")
	if self.Code != http.StatusBadRequest || errorText(t, self) != authutil.ErrSelfAction.Error() {
		t.Errorf("disable self = %d %s, want 400 %q", self.Code, self.Body.String(), authutil.ErrSelfAction.Error())
	}
	for _, path := range []string{"/api/v0/admin/disable/member", "/api/v0/admin/disable/nobody", "/api/v0/admin/enable/admin", "/api/v0/admin/enable/nobody"} {
		if w := h.do(http.MethodPut, path); w.Code != http.StatusNotFound {
			t.Errorf("PUT %s = %d, want 404", path, w.Code)
		}
	}
	if n := h.drainEvents(); n != 0 {
		t.Errorf("refusals published %d events", n)
	}

	if w := h.do(http.MethodPut, "/api/v0/admin/enable/member"); w.Code != http.StatusOK {
		t.Fatalf("enable = %d: %s", w.Code, w.Body.String())
	}
	if n := h.drainEvents(); n != 1 {
		t.Errorf("enable published %d account_changed events, want 1", n)
	}
	if _, err := authutil.Login(ctx, h.database.Queries, authutil.LoginParams{Username: "member", Password: "user-password"}); err != nil {
		t.Errorf("login after enable: %v", err)
	}
}

// TestDisableUser_OnlyActiveAdminIsConflict checks the only active admin cannot
// be turned off, with the sentinel's text. The caller is made a non-admin so
// the request reaches another admin who is the last one; behind RequireAdmin
// this is the guard's defense in depth.
func TestDisableUser_OnlyActiveAdminIsConflict(t *testing.T) {
	h := newAdminHarness(t)
	h.addUser(t, "boss", authutil.StatusActive, true)
	if err := h.database.Queries.SetUserAdmin(context.Background(), db.SetUserAdminParams{IsAdmin: 0, Username: "admin"}); err != nil {
		t.Fatal(err)
	}

	w := h.do(http.MethodPut, "/api/v0/admin/disable/boss")
	if w.Code != http.StatusConflict {
		t.Fatalf("disable the only active admin = %d, want 409: %s", w.Code, w.Body.String())
	}
	if got := errorText(t, w); got != authutil.ErrLastAdmin.Error() {
		t.Errorf("error = %q, want %q", got, authutil.ErrLastAdmin.Error())
	}
}
