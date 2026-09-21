package v0_admin_test

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
)

// TestGroupMembers_Endpoints drives PUT and DELETE
// /admin/groups/:id/members/:userId: a new membership publishes access_changed
// with no path, adding again answers 204 without an event, and each refusal
// answers its status and the sentinel's text without an event.
func TestGroupMembers_Endpoints(t *testing.T) {
	h := newAdminHarness(t)
	ctx := context.Background()
	h.addUser(t, "member", authutil.StatusActive, false)
	h.addUser(t, "waiting", authutil.StatusPending, false)
	userID := func(name string) string {
		t.Helper()
		user, err := h.database.Queries.GetUserByUsername(ctx, name)
		if err != nil {
			t.Fatal(err)
		}
		return strconv.FormatInt(user.ID, 10)
	}
	created, err := grouputil.CreateGroup(ctx, grouputil.CreateGroupParams{Database: h.database, FilesDir: h.filesDir, Name: "Family"})
	if err != nil {
		t.Fatal(err)
	}
	groups, err := grouputil.ListGroups(ctx, grouputil.ListGroupsParams{Database: h.database})
	if err != nil {
		t.Fatal(err)
	}
	family := "/api/v0/admin/groups/" + strconv.FormatInt(created.Group.ID, 10) + "/members/"
	everyone := "/api/v0/admin/groups/" + strconv.FormatInt(groups.Groups[0].ID, 10) + "/members/"
	expect := func(step string, method, path string, code int, err error, events ...eventbus.Event) {
		t.Helper()
		w := h.do(method, path)
		if w.Code != code {
			t.Errorf("%s = %d %s, want %d", step, w.Code, w.Body.String(), code)
		}
		if err != nil && errorText(t, w) != err.Error() {
			t.Errorf("%s error = %q, want %q", step, errorText(t, w), err.Error())
		}
		var got []eventbus.Event
		for len(h.events) > 0 {
			got = append(got, <-h.events)
		}
		if len(got) != len(events) || (len(events) == 1 && got[0] != events[0]) {
			t.Errorf("%s published %v, want %v", step, got, events)
		}
	}
	changed := eventbus.Event{Kind: eventbus.EventAccessChanged}

	expect("add", http.MethodPut, family+userID("member"), http.StatusNoContent, nil, changed)
	expect("add again", http.MethodPut, family+userID("member"), http.StatusNoContent, nil)
	expect("add pending", http.MethodPut, family+userID("waiting"), http.StatusNotFound, authutil.ErrUserNotFound)
	expect("add missing", http.MethodPut, family+"999", http.StatusNotFound, authutil.ErrUserNotFound)
	expect("add to missing group", http.MethodPut, "/api/v0/admin/groups/999/members/"+userID("member"), http.StatusNotFound, grouputil.ErrGroupNotFound)
	expect("add to everyone", http.MethodPut, everyone+userID("member"), http.StatusBadRequest, grouputil.ErrBuiltinGroup)
	expect("remove from everyone", http.MethodDelete, everyone+userID("member"), http.StatusBadRequest, grouputil.ErrBuiltinGroup)

	w := h.do(http.MethodGet, "/api/v0/admin/groups")
	if want := `"members":[{"id":` + userID("member") + `,"username":"member"}]`; w.Code != http.StatusOK || !strings.Contains(w.Body.String(), want) {
		t.Errorf("list = %d %s, want %s", w.Code, w.Body.String(), want)
	}

	expect("remove", http.MethodDelete, family+userID("member"), http.StatusNoContent, nil, changed)
	expect("remove again", http.MethodDelete, family+userID("member"), http.StatusNotFound, grouputil.ErrNotMember)
}
