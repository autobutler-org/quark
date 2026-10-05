package v0_admin_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func (h adminHarness) postJSON(path string, body any) *httptest.ResponseRecorder {
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

// TestCreateUser_Endpoint drives POST /admin/users: an account with a home at
// users/<username> comes back 201 as an active user and announces both the
// account and the folder; a taken name, an existing home and an invalid name
// are refused with the status the app keys its copy off, and a raw password,
// with or without an authKey beside it, is a 426 telling the app to update
// (#2430).
func TestCreateUser_Endpoint(t *testing.T) {
	h := newAdminHarness(t)
	filesDir := h.filesDir
	ctx := context.Background()

	key := dbtest.AuthKey("initial-password")
	w := h.postJSON("/api/v0/admin/users", map[string]any{"username": "bob", "authKey": key})
	if w.Code != http.StatusCreated {
		t.Fatalf("create = %d: %s", w.Code, w.Body.String())
	}
	var created struct {
		ID       int64  `json:"id"`
		Username string `json:"username"`
		IsAdmin  bool   `json:"isAdmin"`
		Status   string `json:"status"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	if created.ID == 0 || created.Username != "bob" || created.IsAdmin || created.Status != authutil.StatusActive {
		t.Errorf("created = %+v, want bob, active, not admin", created)
	}
	if info, err := os.Stat(filepath.Join(filesDir, "users", "bob")); err != nil || !info.IsDir() {
		t.Errorf("private folder: %v", err)
	}
	kinds := map[eventbus.EventKind]string{}
	for len(kinds) < 2 {
		select {
		case evt := <-h.events:
			kinds[evt.Kind] = evt.Path
		default:
			t.Fatalf("events after create = %v, want account_changed and new_folder", kinds)
		}
	}
	if path, ok := kinds[eventbus.EventNewFolder]; !ok || path != "users/bob" {
		t.Errorf("new_folder path = %q (seen %v), want users/bob", path, ok)
	}
	if first, err := authutil.Login(ctx, h.database.Queries, authutil.LoginParams{Username: "bob", AuthKey: key}); err != nil || !first.LegacyRecovery {
		t.Errorf("first login = %+v, %v; want legacyRecovery for the app to give it a recovery key", first, err)
	}

	for _, tc := range []struct {
		name string
		body map[string]any
		want int
		text string
	}{
		{"taken", map[string]any{"username": "bob", "authKey": key}, http.StatusConflict, authutil.ErrUsernameTaken.Error()},
		{"invalid name", map[string]any{"username": "../x", "authKey": key}, http.StatusBadRequest, authutil.ErrInvalidUsername.Error()},
		{"malformed key", map[string]any{"username": "carol", "authKey": "short"}, http.StatusBadRequest, authutil.ErrInvalidAuthKey.Error()},
		{"raw password", map[string]any{"username": "carol", "password": "initial-password"}, http.StatusUpgradeRequired, authutil.ErrAppTooOld.Error()},
		{"raw password beside a key", map[string]any{"username": "carol", "password": "initial-password", "authKey": key}, http.StatusUpgradeRequired, authutil.ErrAppTooOld.Error()},
	} {
		w := h.postJSON("/api/v0/admin/users", tc.body)
		if w.Code != tc.want {
			t.Errorf("%s = %d, want %d: %s", tc.name, w.Code, tc.want, w.Body.String())
			continue
		}
		if got := errorText(t, w); got != tc.text {
			t.Errorf("%s error = %q, want %q", tc.name, got, tc.text)
		}
	}
	if n := h.drainEvents(); n != 0 {
		t.Errorf("refused creates published %d account_changed events", n)
	}
}
