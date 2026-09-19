package accessutil_test

import (
	"context"
	"reflect"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// sharedWithMe lists what the fixture's account is shown under Shared with me.
func (f fixture) sharedWithMe(t *testing.T, principal accessutil.Principal, username string) []accessutil.SharedItem {
	t.Helper()
	result, err := accessutil.ListSharedWithMe(accessutil.ListSharedWithMeParams{
		Ctx:      context.Background(),
		Database: f.database,
		Access:   f.load(t, principal),
		Username: username,
	})
	if err != nil {
		t.Fatalf("ListSharedWithMe: %v", err)
	}
	return result.Items
}

// TestListSharedWithMeKeepsOnlyAdHocShares gives bob a grant in his own home,
// one in a group folder and one somewhere else, and expects only the last: the
// first two are what My files and Groups open.
func TestListSharedWithMeKeepsOnlyAdHocShares(t *testing.T) {
	f := newFixture(t)
	alice := createUser(t, f.database, "alice")
	f.grant(t, f.userID, "", "users/bob", accessutil.Owner)
	f.grant(t, f.userID, "", "users/bob/Taxes", accessutil.Owner)
	f.grant(t, f.userID, "", "groups/family", accessutil.Write)
	f.grant(t, f.userID, "", "groups/family/Trip", accessutil.Write)
	f.grant(t, f.userID, "", "users", accessutil.Read)
	f.grant(t, f.userID, "", "groups", accessutil.Read)
	f.grant(t, f.userID, "", storageutil.TrashPath("gone", ""), accessutil.Read)
	f.grant(t, alice, "", "users/alice", accessutil.Owner)
	f.grant(t, f.userID, "", "users/alice/Photos", accessutil.Read)

	want := []accessutil.SharedItem{
		{RelPath: "users/alice/Photos", Level: "read", Owner: "alice"},
	}
	if got := f.sharedWithMe(t, accessutil.Principal{UserID: f.userID}, "bob"); !reflect.DeepEqual(got, want) {
		t.Errorf("shared with bob = %+v, want %+v", got, want)
	}
}

// TestListSharedWithMeKeepsTheOutermostGrant has bob granted a folder and
// something inside it. Opening the folder reaches both, so only it is listed.
func TestListSharedWithMeKeepsTheOutermostGrant(t *testing.T) {
	f := newFixture(t)
	alice := createUser(t, f.database, "alice")
	f.grant(t, alice, "", "Family", accessutil.Owner)
	f.grant(t, f.userID, "", "Family", accessutil.Read)
	f.grant(t, f.userID, "", "Family/Bob", accessutil.Write)
	f.grant(t, f.userID, "USB-1", "Backups", accessutil.Read)

	want := []accessutil.SharedItem{
		{RelPath: "Family", Level: "read", Owner: "alice"},
		{DeviceSerial: "USB-1", RelPath: "Backups", Level: "read"},
	}
	if got := f.sharedWithMe(t, accessutil.Principal{UserID: f.userID}, "bob"); !reflect.DeepEqual(got, want) {
		t.Errorf("shared with bob = %+v, want %+v", got, want)
	}
}

// TestListSharedWithMeLabelsTheNearestOwner has the share sit inside a folder
// alice owns, with no owner row of its own: the label names her rather than
// leaving the share unattributed.
func TestListSharedWithMeLabelsTheNearestOwner(t *testing.T) {
	f := newFixture(t)
	alice := createUser(t, f.database, "alice")
	carol := createUser(t, f.database, "carol")
	f.grant(t, alice, "", "users/alice", accessutil.Owner)
	f.grant(t, carol, "", "users/alice/Trip/Day1", accessutil.Owner)
	f.grant(t, f.userID, "", "users/alice/Trip", accessutil.Read)

	want := []accessutil.SharedItem{
		{RelPath: "users/alice/Trip", Level: "read", Owner: "alice"},
	}
	if got := f.sharedWithMe(t, accessutil.Principal{UserID: f.userID}, "bob"); !reflect.DeepEqual(got, want) {
		t.Errorf("shared with bob = %+v, want %+v", got, want)
	}
}

// TestListSharedWithMeIsEmptyForAnAdmin checks the answer an admin gets. They
// bypass the access table, so no rows are loaded for them and the shortcut
// stays hidden; All files is how they reach the same folders.
func TestListSharedWithMeIsEmptyForAnAdmin(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "Family", accessutil.Read)

	got := f.sharedWithMe(t, accessutil.Principal{UserID: f.userID, IsAdmin: true}, "bob")
	if len(got) != 0 {
		t.Errorf("shared with an admin = %+v, want none", got)
	}
}

// TestListSharedWithMeWithoutAUsername leaves the caller's name out, which
// leaves their home in: the filter has nothing to recognize it by, and hiding
// every home would hide what alice shared out of hers.
func TestListSharedWithMeWithoutAUsername(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "users/bob", accessutil.Owner)

	want := []accessutil.SharedItem{{RelPath: "users/bob", Level: "owner", Owner: "bob"}}
	if got := f.sharedWithMe(t, accessutil.Principal{UserID: f.userID}, ""); !reflect.DeepEqual(got, want) {
		t.Errorf("shared with a nameless caller = %+v, want %+v", got, want)
	}
}

// TestListSharedWithMeNeedsADatabase checks the guard every accessutil call
// that reads rows carries.
func TestListSharedWithMeNeedsADatabase(t *testing.T) {
	if _, err := accessutil.ListSharedWithMe(accessutil.ListSharedWithMeParams{
		Ctx: context.Background(),
	}); err != accessutil.ErrNoDatabase {
		t.Errorf("ListSharedWithMe with no database = %v, want ErrNoDatabase", err)
	}
}
