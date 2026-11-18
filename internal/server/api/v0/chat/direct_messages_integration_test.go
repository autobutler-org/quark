package v0_chat_test

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"testing"
)

// TestDirectMessageRoutes opens a direct message over HTTP, reuses it, and
// keeps it from an admin outside it on every channel route (#2423).
func TestDirectMessageRoutes(t *testing.T) {
	h := newHarness(t)
	body := `{"userIds":[` + strconv.FormatInt(h.users["carol"], 10) + `]}`
	status, created := h.do(t, http.MethodPost, "/chat/dms", "bob", body)
	if status != http.StatusCreated {
		t.Fatalf("open = %d %s, want 201", status, created)
	}
	var dm struct {
		ID      int64  `json:"id"`
		Kind    string `json:"kind"`
		Members []struct {
			Username string `json:"username"`
		} `json:"members"`
	}
	if err := json.Unmarshal([]byte(created), &dm); err != nil {
		t.Fatal(err)
	}
	if dm.Kind != "dm" || len(dm.Members) != 2 {
		t.Fatalf("open = %s, want a dm with two members", created)
	}
	reopen := `{"userIds":[` + strconv.FormatInt(h.users["bob"], 10) + `]}`
	if status, again := h.do(t, http.MethodPost, "/chat/dms", "carol", reopen); status != http.StatusOK || !strings.Contains(again, `"id":`+strconv.FormatInt(dm.ID, 10)+`,`) {
		t.Errorf("reopen = %d %s, want 200 with channel %d", status, again, dm.ID)
	}
	if status, _ := h.do(t, http.MethodPost, "/chat/dms", "bob", `{"userIds":[]}`); status != http.StatusBadRequest {
		t.Errorf("open with no one = %d, want 400", status)
	}

	id := strconv.FormatInt(dm.ID, 10)
	if _, all := h.do(t, http.MethodGet, "/chat/channels?all=1", "admin", ""); strings.Contains(all, `"id":`+id+`,`) {
		t.Errorf("admin's every-channel list holds the dm: %s", all)
	}
	for _, route := range []struct{ method, path, body string }{
		{http.MethodPatch, "/chat/channels/" + id, `{"name":"spy"}`},
		{http.MethodDelete, "/chat/channels/" + id, ""},
		{http.MethodGet, "/chat/channels/" + id + "/members", ""},
		{http.MethodGet, "/chat/channels/" + id + "/messages", ""},
		{http.MethodGet, "/chat/channels/" + id + "/keys", ""},
		{http.MethodGet, "/chat/channels/" + id + "/events", ""},
		{http.MethodPost, "/chat/channels/" + id + "/typing", ""},
	} {
		if status, got := h.do(t, route.method, route.path, "admin", route.body); status != http.StatusNotFound {
			t.Errorf("admin %s %s = %d %s, want 404", route.method, route.path, status, got)
		}
	}
	if status, _ := h.do(t, http.MethodPatch, "/chat/channels/"+id, "bob", `{"name":"ours"}`); status != http.StatusBadRequest {
		t.Errorf("member renaming the dm = %d, want 400", status)
	}
}
