package accessutil_test

import (
	"context"
	"database/sql"
	"errors"
	"reflect"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// sharing is a fixture with a bus and helpers for the grant calls, acting as
// whichever principal each call names.
type sharing struct {
	fixture
	bus    *eventbus.Bus
	events <-chan eventbus.Event
}

func newSharing(t *testing.T) sharing {
	t.Helper()
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("grants-test")
	t.Cleanup(unsubscribe)
	return sharing{fixture: newFixture(t), bus: bus, events: events}
}

func (s sharing) as(t *testing.T, userID int64) accessutil.Access {
	t.Helper()
	return s.load(t, accessutil.Principal{UserID: userID})
}

func (s sharing) list(t *testing.T, access accessutil.Access, rel string) (accessutil.GrantsResult, error) {
	t.Helper()
	return accessutil.ListGrants(accessutil.ListGrantsParams{Ctx: context.Background(), Database: s.database, Access: access, Path: rel})
}

func (s sharing) set(access accessutil.Access, rel string, userID, groupID int64, level accessutil.Level) (accessutil.GrantsResult, error) {
	return accessutil.SetGrant(accessutil.SetGrantParams{
		Ctx: context.Background(), Database: s.database, EventBus: s.bus, Access: access,
		Path: rel, UserID: userID, GroupID: groupID, Level: level,
	})
}

func (s sharing) revoke(access accessutil.Access, rel string, userID, groupID int64) (accessutil.GrantsResult, error) {
	return accessutil.RevokeGrant(accessutil.RevokeGrantParams{
		Ctx: context.Background(), Database: s.database, EventBus: s.bus, Access: access,
		Path: rel, UserID: userID, GroupID: groupID,
	})
}

// drain returns the events published so far.
func (s sharing) drain() []eventbus.Event {
	var got []eventbus.Event
	for len(s.events) > 0 {
		got = append(got, <-s.events)
	}
	return got
}

func expectErr(t *testing.T, step string, err, want error) {
	t.Helper()
	if !errors.Is(err, want) {
		t.Errorf("%s = %v, want %v", step, err, want)
	}
}

func TestOwnerSharesAndOthersCannot(t *testing.T) {
	s := newSharing(t)
	carol := createUser(t, s.database, "carol")
	dave := createUser(t, s.database, "dave")
	s.grant(t, s.userID, "", "family", accessutil.Owner)
	bob := s.as(t, s.userID)

	if _, err := s.set(bob, "family", carol, 0, accessutil.Read); err != nil {
		t.Fatalf("owner grants read: %v", err)
	}
	result, err := s.set(bob, "/family/", carol, 0, accessutil.Write)
	if err != nil {
		t.Fatalf("owner grants write: %v", err)
	}
	want := accessutil.GrantsResult{
		RelPath: "family", CanManage: true, CanGrantOwner: true,
		Grants: []accessutil.Grant{
			{UserID: s.userID, Name: "bob", Level: "owner", From: "family"},
			{UserID: carol, Name: "carol", Level: "write", From: "family"},
		},
	}
	if !reflect.DeepEqual(result, want) {
		t.Errorf("grants = %+v\nwant %+v", result, want)
	}
	wantEvent := eventbus.Event{Kind: eventbus.EventAccessChanged, Path: "family"}
	if got := s.drain(); len(got) != 2 || got[0] != wantEvent || got[1] != wantEvent {
		t.Errorf("events = %v, want two %v", got, wantEvent)
	}

	// carol writes; dave can't read at all.
	for name, access := range map[string]accessutil.Access{"writer": s.as(t, carol), "reader": readerOf(t, s, "family")} {
		_, err := s.list(t, access, "family")
		expectErr(t, name+" lists", err, accessutil.ErrShareForbidden)
		_, err = s.set(access, "family/sub", dave, 0, accessutil.Read)
		expectErr(t, name+" grants", err, accessutil.ErrShareForbidden)
		_, err = s.revoke(access, "family", s.userID, 0)
		expectErr(t, name+" revokes", err, accessutil.ErrShareForbidden)
	}
	_, err = s.list(t, s.as(t, dave), "family")
	expectErr(t, "stranger lists", err, accessutil.ErrShareNotFound)
	_, err = s.set(s.as(t, dave), "family", dave, 0, accessutil.Owner)
	expectErr(t, "stranger grants", err, accessutil.ErrShareNotFound)
	if got := s.drain(); len(got) != 0 {
		t.Errorf("refusals published %v", got)
	}
}

// readerOf is a new account with read on rel.
func readerOf(t *testing.T, s sharing, rel string) accessutil.Access {
	t.Helper()
	id := createUser(t, s.database, "reader")
	s.grant(t, id, "", rel, accessutil.Read)
	return s.as(t, id)
}

func TestOwnersGrantOwnerButCannotDropTheirOwn(t *testing.T) {
	s := newSharing(t)
	carol := createUser(t, s.database, "carol")
	s.grant(t, s.userID, "", "family", accessutil.Owner)
	bob := s.as(t, s.userID)

	if _, err := s.set(bob, "family", carol, 0, accessutil.Owner); err != nil {
		t.Fatalf("owner grants owner: %v", err)
	}
	_, err := s.set(bob, "family", s.userID, 0, accessutil.Write)
	expectErr(t, "owner demotes self", err, accessutil.ErrSelfOwner)
	_, err = s.revoke(bob, "family", s.userID, 0)
	expectErr(t, "owner revokes self", err, accessutil.ErrSelfOwner)
	if _, err := s.set(bob, "family", s.userID, 0, accessutil.Owner); err != nil {
		t.Errorf("owner re-grants own owner: %v", err)
	}
	// Inherited ownership is not the row on this path, so a subfolder row of
	// their own is theirs to change.
	s.grant(t, s.userID, "", "family/sub", accessutil.Read)
	if _, err := s.revoke(bob, "family/sub", s.userID, 0); err != nil {
		t.Errorf("owner removes own subfolder row: %v", err)
	}

	// A co-owner may demote and then remove the other owner.
	carolAccess := s.as(t, carol)
	if _, err := s.set(carolAccess, "family", s.userID, 0, accessutil.Write); err != nil {
		t.Fatalf("co-owner demotes owner: %v", err)
	}
	_, err = s.list(t, s.as(t, s.userID), "family")
	expectErr(t, "demoted owner lists", err, accessutil.ErrShareForbidden)
	if _, err := s.revoke(carolAccess, "family", s.userID, 0); err != nil {
		t.Errorf("co-owner revokes the other owner: %v", err)
	}

	// An admin may remove the last owner row, and change anyone's.
	result, err := s.revoke(s.load(t, accessutil.System), "family", carol, 0)
	if err != nil || len(result.Grants) != 0 {
		t.Errorf("admin revokes the last owner = %+v, %v", result, err)
	}
	if rows := s.keys(t); len(rows) != 0 {
		t.Errorf("rows left = %v", rows)
	}
}

func TestInheritedGrants(t *testing.T) {
	s := newSharing(t)
	ctx := context.Background()
	carol := createUser(t, s.database, "carol")
	dave := createUser(t, s.database, "dave")
	var everyone int64
	if err := s.database.Db.QueryRow(`SELECT id FROM groups WHERE builtin = 1`).Scan(&everyone); err != nil {
		t.Fatal(err)
	}
	s.grant(t, s.userID, "", "family", accessutil.Owner)
	s.grant(t, carol, "", "", accessutil.Read)
	s.grant(t, carol, "", "family", accessutil.Write)
	s.grant(t, carol, "", "family/sub", accessutil.Read)
	// A sibling whose name starts with the folder's is not a parent of it.
	s.grant(t, carol, "", "family-old", accessutil.Owner)
	if err := s.database.Queries.SetGroupPathAccess(ctx, db.SetGroupPathAccessParams{
		RelPath: "family", GroupID: sql.NullInt64{Int64: everyone, Valid: true}, Level: "read",
	}); err != nil {
		t.Fatal(err)
	}
	bob := s.as(t, s.userID)

	result, err := s.list(t, bob, "family/sub/deep")
	if err != nil {
		t.Fatal(err)
	}
	want := []accessutil.Grant{
		{GroupID: everyone, Name: "everyone", Builtin: true, Level: "read", From: "family"},
		{UserID: s.userID, Name: "bob", Level: "owner", From: "family"},
		{UserID: carol, Name: "carol", Level: "write", From: "family"},
	}
	if !reflect.DeepEqual(result.Grants, want) {
		t.Errorf("inherited grants = %+v\nwant %+v", result.Grants, want)
	}

	result, err = s.list(t, bob, "family/sub")
	if err != nil || len(result.Grants) != 4 || result.Grants[0] != (accessutil.Grant{UserID: carol, Name: "carol", Level: "read", From: "family/sub"}) {
		t.Errorf("grants on family/sub = %+v, %v; want carol's row there first", result.Grants, err)
	}
	if _, err := s.revoke(bob, "family/sub", carol, 0); err != nil {
		t.Errorf("revoke carol's row on family/sub: %v", err)
	}
	_, err = s.revoke(bob, "family/sub", carol, 0)
	expectErr(t, "revoke what family gives", err, accessutil.ErrInheritedGrant)
	_, err = s.revoke(bob, "family/sub", 0, everyone)
	expectErr(t, "revoke everyone's inherited read", err, accessutil.ErrInheritedGrant)
	_, err = s.revoke(bob, "family/sub", dave, 0)
	expectErr(t, "revoke someone with no access", err, accessutil.ErrGrantNotFound)
	if _, err := s.set(bob, "family/sub", carol, 0, accessutil.Read); err != nil {
		t.Errorf("a grant a parent already covers is accepted: %v", err)
	}
}

func TestGrantRefusals(t *testing.T) {
	s := newSharing(t)
	ctx := context.Background()
	s.grant(t, s.userID, "", "family", accessutil.Owner)
	s.grant(t, s.userID, "", ".trash/old", accessutil.Owner)
	bob := s.as(t, s.userID)
	admin := s.load(t, accessutil.System)
	carol := createUser(t, s.database, "carol")
	pending, err := s.database.Queries.CreatePendingUser(ctx, db.CreatePendingUserParams{Username: "pending", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}

	for _, access := range []accessutil.Access{bob, admin} {
		_, err := s.list(t, access, ".trash/old")
		expectErr(t, "list trash", err, accessutil.ErrTrashShare)
		_, err = s.set(access, ".trash/old/x", carol, 0, accessutil.Read)
		expectErr(t, "share trash", err, accessutil.ErrTrashShare)
		_, err = s.revoke(access, "/.trash/old", s.userID, 0)
		expectErr(t, "revoke in trash", err, accessutil.ErrTrashShare)
	}
	_, err = s.set(bob, "family", pending.ID, 0, accessutil.Read)
	expectErr(t, "share with a pending account", err, accessutil.ErrPrincipalNotFound)
	_, err = s.set(bob, "family", 999, 0, accessutil.Read)
	expectErr(t, "share with a missing account", err, accessutil.ErrPrincipalNotFound)
	_, err = s.set(bob, "family", 0, 999, accessutil.Read)
	expectErr(t, "share with a missing group", err, accessutil.ErrPrincipalNotFound)
	_, err = s.set(bob, "family", carol, 1, accessutil.Read)
	expectErr(t, "share with both", err, accessutil.ErrGrantTarget)
	_, err = s.revoke(bob, "family", 0, 0)
	expectErr(t, "revoke nobody", err, accessutil.ErrGrantTarget)
	_, err = s.set(bob, "family", carol, 0, accessutil.None)
	expectErr(t, "share at no level", err, accessutil.ErrInvalidLevel)
	if got := s.drain(); len(got) != 0 {
		t.Errorf("refusals published %v", got)
	}
}

// A grant on users or groups itself would reach every home or every group
// folder, so nobody may make one, admins included (#2016). Folders inside them
// share as usual, and a row already on a root can still be removed.
func TestStructuralRootsCannotBeShared(t *testing.T) {
	s := newSharing(t)
	s.grant(t, s.userID, "", "users", accessutil.Owner)
	s.grant(t, s.userID, "", "groups", accessutil.Owner)
	bob := s.as(t, s.userID)
	admin := s.load(t, accessutil.System)
	carol := createUser(t, s.database, "carol")

	for name, access := range map[string]accessutil.Access{"member": bob, "admin": admin} {
		for _, rel := range []string{"users", "/groups/", "./users", "groups/."} {
			_, err := s.set(access, rel, carol, 0, accessutil.Read)
			expectErr(t, name+" shares "+rel, err, accessutil.ErrStructuralShare)
		}
	}
	if got := s.drain(); len(got) != 0 {
		t.Errorf("refusals published %v", got)
	}
	for _, rel := range []string{"users/carol", "groups/Family"} {
		if _, err := s.set(admin, rel, carol, 0, accessutil.Read); err != nil {
			t.Errorf("admin shares %s: %v", rel, err)
		}
	}
	if _, err := s.revoke(admin, "users", s.userID, 0); err != nil {
		t.Errorf("admin removes a row already on users: %v", err)
	}
}
