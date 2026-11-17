// cspell:words thumbversionutil

package v0_users_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	v0_users "github.com/autobutler-org/quark/internal/server/api/v0/users"
	"github.com/autobutler-org/quark/pkg/util/thumbversionutil"
)

// TestGetAvatar_VersionedIsImmutable: a picture URL whose v is the current
// avatarUpdatedAt is cacheable as immutable and private; without v, or with a
// stale one, it is revalidated as before (#4217).
func TestGetAvatar_VersionedIsImmutable(t *testing.T) {
	h := newHarness(t)
	w := h.upload(t, jpegWithExif(t, 64, 64))
	if w.Code != http.StatusOK {
		t.Fatalf("PUT = %d: %s", w.Code, w.Body.String())
	}
	var resp v0_users.SetAvatarResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}

	for _, tc := range []struct{ query, want string }{
		{"", "no-cache"},
		{fmt.Sprintf("?v=%d", resp.AvatarUpdatedAt), thumbversionutil.Immutable},
		{fmt.Sprintf("?v=%d", resp.AvatarUpdatedAt-1), "no-cache"},
	} {
		got := h.do(httptest.NewRequest(http.MethodGet, "/api/v0/users/7/avatar"+tc.query, nil))
		if got.Code != http.StatusOK {
			t.Fatalf("GET%s = %d", tc.query, got.Code)
		}
		if cc := got.Header().Get("Cache-Control"); cc != tc.want {
			t.Errorf("GET%s: Cache-Control = %q, want %q", tc.query, cc, tc.want)
		}
	}
}
