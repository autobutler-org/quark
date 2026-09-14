package v0_admin_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestDeleteUser_Endpoint drives DELETE /admin/users/:username: the account
// goes, the calling admin inherits what it owned, and account_changed is
// published. A second delete is 404 and the caller's own account is 400.
func TestDeleteUser_Endpoint(t *testing.T) {
	h := newAdminHarness(t)
	ctx := context.Background()
	h.addUser(t, "member", authutil.StatusActive, false)
	member, err := h.database.Queries.GetUserByUsername(ctx, "member")
	if err != nil {
		t.Fatal(err)
	}
	if err := h.database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		RelPath: "member", UserID: sql.NullInt64{Int64: member.ID, Valid: true}, Level: "owner",
	}); err != nil {
		t.Fatal(err)
	}

	w := h.do(http.MethodDelete, "/api/v0/admin/users/member")
	if w.Code != http.StatusOK {
		t.Fatalf("delete = %d: %s", w.Code, w.Body.String())
	}
	var body struct {
		OwnerRowsReassigned int64 `json:"ownerRowsReassigned"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil || body.OwnerRowsReassigned != 1 {
		t.Errorf("body = %s (%v), want ownerRowsReassigned 1", w.Body.String(), err)
	}
	if n := h.drainEvents(); n != 1 {
		t.Errorf("delete published %d account_changed events, want 1", n)
	}
	rows, err := h.database.Queries.ListPathAccessForUser(ctx, sql.NullInt64{Int64: h.adminID, Valid: true})
	if err != nil || len(rows) != 1 || rows[0].RelPath != "member" || rows[0].Level != "owner" {
		t.Errorf("admin's rows = %+v (%v), want owner of member", rows, err)
	}

	if w := h.do(http.MethodDelete, "/api/v0/admin/users/member"); w.Code != http.StatusNotFound {
		t.Errorf("delete again = %d, want 404", w.Code)
	}
	self := h.do(http.MethodDelete, "/api/v0/admin/users/admin")
	if self.Code != http.StatusBadRequest || errorText(t, self) != authutil.ErrSelfAction.Error() {
		t.Errorf("delete self = %d %s, want 400", self.Code, self.Body.String())
	}
	if n := h.drainEvents(); n != 0 {
		t.Errorf("refusals published %d events", n)
	}
}

// TestDeleteUser_OnlyActiveAdminIsConflict checks the only active admin cannot
// be deleted while other accounts exist. The caller is made a non-admin so the
// request can name another admin who is the last one.
func TestDeleteUser_OnlyActiveAdminIsConflict(t *testing.T) {
	h := newAdminHarness(t)
	h.addUser(t, "boss", authutil.StatusActive, true)
	if err := h.database.Queries.SetUserAdmin(context.Background(), db.SetUserAdminParams{IsAdmin: 0, Username: "admin"}); err != nil {
		t.Fatal(err)
	}

	w := h.do(http.MethodDelete, "/api/v0/admin/users/boss")
	if w.Code != http.StatusConflict || errorText(t, w) != authutil.ErrLastAdmin.Error() {
		t.Errorf("delete the only active admin = %d %s, want 409", w.Code, w.Body.String())
	}
}
