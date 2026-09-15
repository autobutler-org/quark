package v0_admin_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestApproveUser_PendingOnly checks approving a pending request lets it sign
// in and publishes account_changed, and approving anything else is 404.
func TestApproveUser_PendingOnly(t *testing.T) {
	h := newAdminHarness(t)
	ctx := context.Background()
	h.addUser(t, "waiting", authutil.StatusPending, false)
	h.addUser(t, "off", authutil.StatusDisabled, false)

	if w := h.do(http.MethodPut, "/api/v0/admin/approve/waiting"); w.Code != http.StatusOK {
		t.Fatalf("approve = %d: %s", w.Code, w.Body.String())
	}
	if n := h.drainEvents(); n != 1 {
		t.Errorf("approve published %d account_changed events, want 1", n)
	}
	if _, err := authutil.Login(ctx, h.database.Queries, authutil.LoginParams{Username: "waiting", Password: "user-password"}); err != nil {
		t.Errorf("login after approval: %v", err)
	}

	for _, name := range []string{"waiting", "off", "admin", "nobody"} {
		w := h.do(http.MethodPut, "/api/v0/admin/approve/"+name)
		if w.Code != http.StatusNotFound {
			t.Errorf("approve %s = %d, want 404", name, w.Code)
		} else if got := errorText(t, w); got != authutil.ErrRequestNotFound.Error() {
			t.Errorf("approve %s error = %q", name, got)
		}
	}
	if n := h.drainEvents(); n != 0 {
		t.Errorf("refused approvals published %d events", n)
	}
}

// TestDenyUser_PendingOnly checks denying a pending request deletes it and
// publishes account_changed, and denying an account that is not pending is 404
// and leaves it in place.
func TestDenyUser_PendingOnly(t *testing.T) {
	h := newAdminHarness(t)
	ctx := context.Background()
	h.addUser(t, "asker", authutil.StatusPending, false)
	h.addUser(t, "off", authutil.StatusDisabled, false)

	if w := h.do(http.MethodPut, "/api/v0/admin/deny/asker"); w.Code != http.StatusOK {
		t.Fatalf("deny = %d: %s", w.Code, w.Body.String())
	}
	if n := h.drainEvents(); n != 1 {
		t.Errorf("deny published %d account_changed events, want 1", n)
	}
	if _, err := h.database.Queries.GetUserByUsername(ctx, "asker"); err == nil {
		t.Error("denied request is still a row")
	}

	for _, name := range []string{"asker", "off", "admin"} {
		if w := h.do(http.MethodPut, "/api/v0/admin/deny/"+name); w.Code != http.StatusNotFound {
			t.Errorf("deny %s = %d, want 404", name, w.Code)
		}
	}
	for _, name := range []string{"off", "admin"} {
		if _, err := h.database.Queries.GetUserByUsername(ctx, name); err != nil {
			t.Errorf("refused deny removed %s: %v", name, err)
		}
	}
}
