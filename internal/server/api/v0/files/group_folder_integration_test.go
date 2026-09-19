package v0_files_test

import (
	"context"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
)

// A group's folder, groups/<name>, carries the group's grant. A member moving
// or trashing it would take the whole group's space with it (#2016).

// newGroupHarness is bob in the Family group, whose folder holds two files,
// and in no group for Friends.
func newGroupHarness(t *testing.T, admin bool) accessHarness {
	t.Helper()
	h := newAccessHarness(t, admin)
	ctx := context.Background()
	for _, name := range []string{"Family", "Friends"} {
		created, err := grouputil.CreateGroup(ctx, grouputil.CreateGroupParams{Database: h.database, FilesDir: h.filesDir, Name: name})
		if err != nil {
			t.Fatal(err)
		}
		if name != "Family" {
			continue
		}
		if _, err := h.database.Queries.AddGroupMember(ctx, db.AddGroupMemberParams{GroupID: created.Group.ID, UserID: h.userID}); err != nil {
			t.Fatal(err)
		}
	}
	writeFixture(t, h.filesDir, "groups/Family/notes.txt")
	writeFixture(t, h.filesDir, "groups/Family/sub/deep.txt")
	return h
}

func TestGroupFolder_MemberCannotDeleteOrMoveIt(t *testing.T) {
	h := newGroupHarness(t, false)
	before := h.levels(t)

	expectCodes(t, http.StatusForbidden, map[string]*httptest.ResponseRecorder{
		"delete":                h.del("groups", "Family"),
		"delete, full path":     h.del("", "groups/Family"),
		"delete, unclean":       h.del("", "/groups/./Family/"),
		"batch with the folder": h.delMany("", "", "groups/Family/notes.txt", "groups/Family"),
		"rename":                h.move("groups/Family", "groups/Family2"),
		"move inside itself":    h.move("groups/Family", "groups/Family/sub/x"),
	})
	// A group bob is not in reads as nothing there at all.
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"delete another group's folder": h.del("groups", "Friends"),
		"move another group's folder":   h.move("groups/Friends", "groups/Mine"),
	})

	expectExists(t, h.filesDir, "groups/Family/notes.txt", "groups/Family/sub/deep.txt", "groups/Friends")
	if got := h.levels(t); !maps.Equal(got, before) {
		t.Errorf("rows = %v, want them untouched: %v", got, before)
	}
}

func TestGroupFolder_MemberManagesWhatIsInsideIt(t *testing.T) {
	h := newGroupHarness(t, false)

	if w := h.move("groups/Family/notes.txt", "groups/Family/sub/renamed.txt"); w.Code != http.StatusOK {
		t.Fatalf("move a file inside = %d: %s", w.Code, w.Body.String())
	}
	if w := h.delMany("", "groups/Family", "sub"); w.Code != http.StatusOK {
		t.Fatalf("delete inside = %d: %s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(filepath.Join(h.filesDir, "groups", "Family", "sub")); !os.IsNotExist(err) {
		t.Errorf("groups/Family/sub still exists after delete: %v", err)
	}
	expectExists(t, h.filesDir, "groups/Family")
}

func TestGroupFolder_AdminCanDeleteIt(t *testing.T) {
	h := newGroupHarness(t, true)

	if w := h.del("groups", "Family"); w.Code != http.StatusOK {
		t.Fatalf("admin delete = %d: %s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(filepath.Join(h.filesDir, "groups", "Family")); !os.IsNotExist(err) {
		t.Errorf("groups/Family still exists after an admin delete: %v", err)
	}
}
