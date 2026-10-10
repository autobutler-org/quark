package v0_admin_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/requestlogutil"
)

// TestApproveUser_PendingOnly checks approving a pending request lets it sign
// in, gives it the home it owns, and publishes account_changed, and that
// approving anything else is 404.
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
	if _, err := authutil.Login(ctx, h.database.Queries, authutil.LoginParams{Username: "waiting", AuthKey: dbtest.AuthKey("user-password")}); err != nil {
		t.Errorf("login after approval: %v", err)
	}
	// The grant is what an upload is checked against, so it matters more than
	// the directory: without it the approved account is refused every write.
	if info, err := h.files.Stat(ctx, "users/waiting"); err != nil || !info.IsDir {
		t.Errorf("home of the approved account: %v", err)
	}
	var level string
	if err := h.database.Db.QueryRow(`SELECT level FROM path_access WHERE rel_path = 'users/waiting'`).Scan(&level); err != nil {
		t.Errorf("the approved account owns no path: %v", err)
	} else if level != "owner" {
		t.Errorf("grant on users/waiting = %q, want owner", level)
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

// TestListAccountRequestHistory_RecordsDecisions checks the history starts
// empty, gains one entry per approval and denial with the admin who made it,
// newest first, and gains nothing from a decision that was refused.
func TestListAccountRequestHistory_RecordsDecisions(t *testing.T) {
	h := newAdminHarness(t)
	h.addUser(t, "waiting", authutil.StatusPending, false)
	h.addUser(t, "asker", authutil.StatusPending, false)

	history := func() []requestlogutil.Entry {
		t.Helper()
		w := h.do(http.MethodGet, "/api/v0/admin/account-requests/history")
		if w.Code != http.StatusOK {
			t.Fatalf("history = %d: %s", w.Code, w.Body.String())
		}
		var entries []requestlogutil.Entry
		if err := json.Unmarshal(w.Body.Bytes(), &entries); err != nil {
			t.Fatalf("decode %q: %v", w.Body.String(), err)
		}
		if entries == nil {
			t.Fatalf("history body = %q, want a JSON array", w.Body.String())
		}
		return entries
	}

	if entries := history(); len(entries) != 0 {
		t.Fatalf("history before any decision = %+v", entries)
	}

	before := time.Now().Add(-time.Second)
	if w := h.do(http.MethodPut, "/api/v0/admin/approve/waiting"); w.Code != http.StatusOK {
		t.Fatalf("approve = %d: %s", w.Code, w.Body.String())
	}
	if w := h.do(http.MethodPut, "/api/v0/admin/deny/asker"); w.Code != http.StatusOK {
		t.Fatalf("deny = %d: %s", w.Code, w.Body.String())
	}
	// Neither names a pending request any more, so neither is a decision.
	h.do(http.MethodPut, "/api/v0/admin/approve/asker")
	h.do(http.MethodPut, "/api/v0/admin/deny/waiting")

	entries := history()
	if len(entries) != 2 {
		t.Fatalf("history = %+v, want the denial then the approval", entries)
	}
	want := []struct{ username, outcome string }{
		{"asker", requestlogutil.OutcomeDenied},
		{"waiting", requestlogutil.OutcomeApproved},
	}
	for i, entry := range entries {
		if entry.Username != want[i].username || entry.Outcome != want[i].outcome || entry.DecidedBy != "admin" {
			t.Errorf("history[%d] = %+v, want %s %s by admin", i, entry, want[i].username, want[i].outcome)
		}
		if entry.DecidedAt.Before(before) || entry.DecidedAt.After(time.Now().Add(time.Second)) {
			t.Errorf("history[%d] decided at %v, want about now", i, entry.DecidedAt)
		}
	}
}
