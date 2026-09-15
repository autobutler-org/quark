package grouputil_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// fakeDetector is one internal device at mountPoint.
type fakeDetector struct {
	mountPoint string
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Device", MountPoint: f.mountPoint, IsInternal: true}}, nil
}

func addUser(t *testing.T, database *db.DatabaseSqlc, username, status string) int64 {
	t.Helper()
	ctx := context.Background()
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: username, PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	if status != authutil.StatusActive {
		if _, err := database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{Username: username, FromStatus: authutil.StatusActive, ToStatus: status}); err != nil {
			t.Fatal(err)
		}
	}
	return user.ID
}

// TestMembers checks adding is idempotent, only an active account can join,
// everyone's members can't change, removing a non-member is refused, and the
// access a member loads follows their membership.
func TestMembers(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	mountPoint := t.TempDir()
	if err := os.MkdirAll(filepath.Join(mountPoint, "quark", "data", "files", "shared"), 0o755); err != nil {
		t.Fatal(err)
	}
	storage := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	family := create(t, database, "Family")
	bob := addUser(t, database, "bob", authutil.StatusActive)
	pending := addUser(t, database, "pending", authutil.StatusPending)
	disabled := addUser(t, database, "disabled", authutil.StatusDisabled)
	if _, err := database.Db.Exec(`INSERT INTO path_access (rel_path, group_id, level) VALUES ('shared', ?, 'write')`, family.ID); err != nil {
		t.Fatal(err)
	}
	level := func() accessutil.Level {
		t.Helper()
		loaded, err := accessutil.Load(accessutil.LoadParams{Ctx: ctx, Database: database, Storage: storage, Principal: accessutil.Principal{UserID: bob}})
		if err != nil {
			t.Fatal(err)
		}
		return loaded.Access.Level("", "shared/file.txt")
	}
	add := func(groupID, userID int64) (grouputil.AddMemberResult, error) {
		return grouputil.AddMember(ctx, grouputil.AddMemberParams{Database: database, GroupID: groupID, UserID: userID})
	}
	remove := func(groupID, userID int64) error {
		_, err := grouputil.RemoveMember(ctx, grouputil.RemoveMemberParams{Database: database, GroupID: groupID, UserID: userID})
		return err
	}

	if got := level(); got != accessutil.None {
		t.Fatalf("level before joining = %v", got)
	}
	if result, err := add(family.ID, bob); err != nil || !result.Added {
		t.Fatalf("add = %+v, %v", result, err)
	}
	if result, err := add(family.ID, bob); err != nil || result.Added {
		t.Errorf("add again = %+v, %v; want no error and nothing added", result, err)
	}
	if got := level(); got != accessutil.Write {
		t.Errorf("level as a member = %v, want write", got)
	}

	for name, userID := range map[string]int64{"pending": pending, "disabled": disabled, "missing": 999} {
		if _, err := add(family.ID, userID); !errors.Is(err, authutil.ErrUserNotFound) {
			t.Errorf("add %s = %v, want ErrUserNotFound", name, err)
		}
	}
	if _, err := add(everyoneID(t, database), bob); !errors.Is(err, grouputil.ErrBuiltinGroup) {
		t.Errorf("add to everyone = %v, want ErrBuiltinGroup", err)
	}
	if err := remove(everyoneID(t, database), bob); !errors.Is(err, grouputil.ErrBuiltinGroup) {
		t.Errorf("remove from everyone = %v, want ErrBuiltinGroup", err)
	}
	if _, err := add(999, bob); !errors.Is(err, grouputil.ErrGroupNotFound) {
		t.Errorf("add to a missing group = %v, want ErrGroupNotFound", err)
	}

	// A member who is turned off keeps the membership.
	if _, err := add(family.ID, addUser(t, database, "carol", authutil.StatusActive)); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{Username: "carol", FromStatus: authutil.StatusActive, ToStatus: authutil.StatusDisabled}); err != nil {
		t.Fatal(err)
	}
	listed, err := grouputil.ListGroups(ctx, grouputil.ListGroupsParams{Database: database})
	if err != nil || len(listed.Groups) != 2 || len(listed.Groups[1].Members) != 2 {
		t.Errorf("groups = %+v, %v; want Family listing bob and the disabled carol", listed, err)
	}

	if err := remove(family.ID, bob); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if err := remove(family.ID, bob); !errors.Is(err, grouputil.ErrNotMember) {
		t.Errorf("remove again = %v, want ErrNotMember", err)
	}
	if got := level(); got != accessutil.None {
		t.Errorf("level after leaving = %v, want none", got)
	}
}
