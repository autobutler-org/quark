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

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
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
// are refused with the status the app keys its copy off.
func TestCreateUser_Endpoint(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	h := newAdminHarness(t)
	ctx := context.Background()

	w := h.postJSON("/api/v0/admin/users", map[string]any{"username": "bob", "password": "initial-password", "createFolder": true})
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
	if first, err := authutil.Login(ctx, h.database.Queries, authutil.LoginParams{Username: "bob", Password: "initial-password"}); err != nil || first.RecoveryPhrase == "" {
		t.Errorf("first login = %+v, %v; want a recovery phrase", first, err)
	}

	if err := os.MkdirAll(filepath.Join(filesDir, "users", "family"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name string
		body map[string]any
		want int
		text string
	}{
		{"taken", map[string]any{"username": "bob", "password": "initial-password"}, http.StatusConflict, authutil.ErrUsernameTaken.Error()},
		{"folder exists", map[string]any{"username": "family", "password": "initial-password", "createFolder": true}, http.StatusConflict, authutil.ErrFolderExists.Error()},
		{"invalid name", map[string]any{"username": "../x", "password": "initial-password"}, http.StatusBadRequest, authutil.ErrInvalidUsername.Error()},
		{"short password", map[string]any{"username": "carol", "password": "short"}, http.StatusBadRequest, authutil.ErrPasswordTooShort.Error()},
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
	if _, err := h.database.Queries.GetUserByUsername(ctx, "family"); err == nil {
		t.Error("the folder conflict still created the account")
	}
}
