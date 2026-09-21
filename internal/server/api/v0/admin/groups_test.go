package v0_admin_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
)

func (h adminHarness) doJSON(method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

// drainKinds lists the kinds of the events published so far.
func (h adminHarness) drainKinds() []eventbus.EventKind {
	var kinds []eventbus.EventKind
	for {
		select {
		case evt := <-h.events:
			kinds = append(kinds, evt.Kind)
		default:
			return kinds
		}
	}
}

func decodeGroup(t *testing.T, w *httptest.ResponseRecorder) grouputil.Group {
	t.Helper()
	var group grouputil.Group
	if err := json.Unmarshal(w.Body.Bytes(), &group); err != nil {
		t.Fatalf("decode %q: %v", w.Body.String(), err)
	}
	return group
}

// TestGroups_Endpoints drives create, list, rename and delete: each success
// answers with its status and event, and each refusal with its status, the
// sentinel's text, and no event.
func TestGroups_Endpoints(t *testing.T) {
	h := newAdminHarness(t)
	one := func(kind eventbus.EventKind) []eventbus.EventKind { return []eventbus.EventKind{kind} }
	expectEvents := func(step string, want []eventbus.EventKind) {
		t.Helper()
		if got := h.drainKinds(); !slices.Equal(got, want) {
			t.Errorf("%s published %v, want %v", step, got, want)
		}
	}
	expectError := func(step string, w *httptest.ResponseRecorder, code int, err error) {
		t.Helper()
		if w.Code != code || errorText(t, w) != err.Error() {
			t.Errorf("%s = %d %s, want %d %q", step, w.Code, w.Body.String(), code, err.Error())
		}
	}

	w := h.doJSON(http.MethodPost, "/api/v0/admin/groups", `{"name":" Family "}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("create = %d: %s", w.Code, w.Body.String())
	}
	family := decodeGroup(t, w)
	if family.Name != "Family" || family.Builtin || family.Members == nil {
		t.Errorf("created %+v", family)
	}
	expectEvents("create", []eventbus.EventKind{eventbus.EventAccountChanged, eventbus.EventNewFolder})
	expectDir := func(step, rel string, want bool) {
		t.Helper()
		info, err := os.Stat(filepath.Join(h.filesDir, filepath.FromSlash(rel)))
		if got := err == nil && info.IsDir(); got != want {
			t.Errorf("%s: %s is a folder = %v, want %v", step, rel, got, want)
		}
	}
	expectDir("create", "groups/Family", true)
	familyPath := "/api/v0/admin/groups/" + strconv.FormatInt(family.ID, 10)

	expectError("create taken", h.doJSON(http.MethodPost, "/api/v0/admin/groups", `{"name":"FAMILY"}`), http.StatusConflict, grouputil.ErrGroupNameTaken)
	expectError("create empty", h.doJSON(http.MethodPost, "/api/v0/admin/groups", `{"name":""}`), http.StatusBadRequest, grouputil.ErrInvalidGroupName)
	expectError("create no body", h.doJSON(http.MethodPost, "/api/v0/admin/groups", ``), http.StatusBadRequest, grouputil.ErrInvalidGroupName)
	expectError("create traversal", h.doJSON(http.MethodPost, "/api/v0/admin/groups", `{"name":"../escape"}`), http.StatusBadRequest, grouputil.ErrInvalidGroupName)
	expectDir("create traversal", "escape", false)
	expectEvents("refused creates", nil)

	w = h.do(http.MethodGet, "/api/v0/admin/groups")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"name":"everyone","builtin":true,"members":[]`) {
		t.Errorf("list = %d %s, want everyone with members []", w.Code, w.Body.String())
	}
	var groups []grouputil.Group
	if err := json.Unmarshal(w.Body.Bytes(), &groups); err != nil || len(groups) != 2 || groups[1].Name != "Family" {
		t.Fatalf("list = %s, %v", w.Body.String(), err)
	}
	everyonePath := "/api/v0/admin/groups/" + strconv.FormatInt(groups[0].ID, 10)

	w = h.doJSON(http.MethodPut, familyPath, `{"name":"Household"}`)
	if w.Code != http.StatusOK || decodeGroup(t, w).Name != "Household" {
		t.Errorf("rename = %d %s", w.Code, w.Body.String())
	}
	// The folder moves like any other move, carrying the group's grant.
	expectEvents("rename", []eventbus.EventKind{eventbus.EventMove, eventbus.EventAccessChanged, eventbus.EventAccountChanged})
	expectDir("rename", "groups/Family", false)
	expectDir("rename", "groups/Household", true)
	if err := os.Mkdir(filepath.Join(h.filesDir, "groups", "Taken"), 0o755); err != nil {
		t.Fatal(err)
	}
	expectError("rename onto a folder", h.doJSON(http.MethodPut, familyPath, `{"name":"Taken"}`), http.StatusConflict, grouputil.ErrGroupFolderTaken)
	expectError("rename everyone", h.doJSON(http.MethodPut, everyonePath, `{"name":"all"}`), http.StatusBadRequest, grouputil.ErrBuiltinGroup)
	expectError("rename invalid", h.doJSON(http.MethodPut, familyPath, `{"name":"a\nb"}`), http.StatusBadRequest, grouputil.ErrInvalidGroupName)
	expectError("rename onto everyone", h.doJSON(http.MethodPut, familyPath, `{"name":"Everyone"}`), http.StatusConflict, grouputil.ErrGroupNameTaken)
	expectError("rename missing", h.doJSON(http.MethodPut, "/api/v0/admin/groups/999", `{"name":"x"}`), http.StatusNotFound, grouputil.ErrGroupNotFound)
	expectError("rename non-numeric", h.doJSON(http.MethodPut, "/api/v0/admin/groups/abc", `{"name":"x"}`), http.StatusNotFound, grouputil.ErrGroupNotFound)
	expectEvents("refused renames", nil)

	expectError("delete everyone", h.do(http.MethodDelete, everyonePath), http.StatusBadRequest, grouputil.ErrBuiltinGroup)
	expectEvents("refused delete", nil)
	if w := h.do(http.MethodDelete, familyPath); w.Code != http.StatusNoContent {
		t.Errorf("delete = %d %s, want 204", w.Code, w.Body.String())
	}
	expectEvents("delete", one(eventbus.EventAccessChanged))
	expectDir("delete keeps the folder", "groups/Household", true)
	expectError("delete again", h.do(http.MethodDelete, familyPath), http.StatusNotFound, grouputil.ErrGroupNotFound)
}
