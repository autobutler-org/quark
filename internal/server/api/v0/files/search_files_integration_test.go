package v0_files_test

import (
	"slices"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

// A member who cannot read another member's home finds nothing in it by
// name, and an empty query answers nothing at all (#2758).
func TestSearchFiles_OtherHomeAndEmptyQuery(t *testing.T) {
	h := newAccessHarness(t, false)
	for _, rel := range []string{"users/bob/notes.txt", "users/carol/secret.txt", "users/carol/notes.txt"} {
		writeFixture(t, h.filesDir, rel)
	}
	h.grant(t, "users/bob", accessutil.Owner)

	if got := h.paths(t, "/api/v0/files/search?query=.txt"); !slices.Equal(got, []string{"users/bob/notes.txt"}) {
		t.Errorf("search .txt = %v, want only bob's own file", got)
	}
	if got := h.paths(t, "/api/v0/files/search?query=secret"); len(got) != 0 {
		t.Errorf("search secret = %v, want nothing from carol's home", got)
	}
	for _, query := range []string{"", "%20"} {
		if got := h.paths(t, "/api/v0/files/search?query="+query); len(got) != 0 {
			t.Errorf("search %q = %v, want nothing", query, got)
		}
	}
}
