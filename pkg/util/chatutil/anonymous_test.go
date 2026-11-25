package chatutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
)

// TestAnonymousPseudonymsAreStableAndOpaque checks that an anonymous
// channel's pseudonyms (#2949) are negative, exact in a JSON number, distinct,
// and the same on every read, that a group's accounts get them too, and that
// a member without manage_members sees accounts only by alias, in alias order.
func TestAnonymousPseudonymsAreStableAndOpaque(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	created, err := chatutil.CreateChannel(chatutil.CreateChannelParams{
		Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("bob"), Name: "masks", Anonymous: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	room := created.Channel
	if !room.Anonymous || room.SelfID >= 0 || room.SelfID < -(1<<53) {
		t.Fatalf("created %+v", room)
	}
	if err := f.set(t, "bob", room.ID, f.users["carol"], 0, chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", room.ID, 0, f.group(t, "crew", "dave"), chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}

	list := func(as string) chatutil.ListMembersResult {
		t.Helper()
		result, err := chatutil.ListMembers(chatutil.ListMembersParams{Ctx: ctx, Database: f.database, Principal: f.as(as), ChannelID: room.ID})
		if err != nil {
			t.Fatal(err)
		}
		return result
	}
	seen := map[int64]bool{}
	byUser := map[int64]int64{}
	for _, m := range list("bob").Members {
		people := []chatutil.MemberUser{{ID: m.UserID, PseudonymID: m.PseudonymID}}
		if m.GroupID != 0 {
			people = m.Users
		}
		for _, u := range people {
			if u.ID <= 0 || u.PseudonymID >= 0 || seen[u.PseudonymID] {
				t.Errorf("bob sees %+v", u)
			}
			seen[u.PseudonymID] = true
			byUser[u.ID] = u.PseudonymID
		}
	}
	if byUser[f.users["bob"]] != room.SelfID || len(byUser) != 3 {
		t.Errorf("pseudonyms = %v, want bob's to be his selfId and one each for bob, carol and dave", byUser)
	}

	carol := list("carol").Members
	last := ""
	for _, m := range carol {
		if m.GroupID != 0 {
			continue
		}
		if m.UserID >= 0 || m.UserID != m.PseudonymID || m.Name != m.Alias || m.AvatarUpdatedAt != 0 {
			t.Errorf("carol sees %+v", m)
		}
		if m.Name < last {
			t.Errorf("carol's accounts are not in alias order: %q after %q", m.Name, last)
		}
		last = m.Name
	}
	again := list("carol").Members
	for i := range carol {
		if carol[i].UserID != again[i].UserID {
			t.Errorf("pseudonym moved between reads: %+v then %+v", carol[i], again[i])
		}
	}

	// A pseudonym nobody holds names no one, and an alias is only for
	// anonymous channels.
	if err := f.remove("bob", room.ID, -1, 0); !errors.Is(err, chatutil.ErrMemberNotFound) {
		t.Errorf("removing an unknown pseudonym = %v, want ErrMemberNotFound", err)
	}
	plain := f.create(t, "bob", "plain")
	_, err = chatutil.SetAlias(chatutil.SetAliasParams{
		Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: plain.ID, UserID: f.users["bob"], Alias: "Fox",
	})
	if !errors.Is(err, chatutil.ErrNotAnonymous) {
		t.Errorf("alias on a plain channel = %v, want ErrNotAnonymous", err)
	}
}

// anonymousRoom is an anonymous channel bob made, with carol a viewer on her
// own row and dave reached only through a group of one.
func anonymousRoom(t *testing.T, f fixture) (room chatutil.Channel, crew int64) {
	t.Helper()
	created, err := chatutil.CreateChannel(chatutil.CreateChannelParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as("bob"), Name: "masks", Anonymous: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	crew = f.group(t, "crew", "dave")
	if err := f.set(t, "bob", created.Channel.ID, f.users["carol"], 0, chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", created.Channel.ID, 0, crew, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}
	return created.Channel, crew
}

// TestAnonymousGroupRowsNameNoOne checks that a member without
// manage_members gets no group-to-account mapping in an anonymous channel
// (#2949): a group row carries no users, and every account the rows reach is
// its own account row, under its pseudonym, with its effective set. Otherwise
// a group of one, or comparing which groups a pseudonym is in against a
// channel that isn't anonymous, unmasks it.
func TestAnonymousGroupRowsNameNoOne(t *testing.T) {
	f := newFixture(t)
	room, crew := anonymousRoom(t, f)
	result, err := chatutil.ListMembers(chatutil.ListMembersParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: room.ID})
	if err != nil {
		t.Fatal(err)
	}
	accounts := map[int64]chatutil.Perms{}
	for _, m := range result.Members {
		if m.GroupID != 0 {
			if m.GroupID != crew || m.Users != nil {
				t.Errorf("carol sees group row %+v, want crew with no users", m)
			}
			continue
		}
		if m.UserID >= 0 || m.UserID != m.PseudonymID || m.Name != m.Alias {
			t.Errorf("carol sees account row %+v, want a pseudonym", m)
		}
		accounts[m.UserID] = m.Permissions
	}
	if len(accounts) != 3 {
		t.Fatalf("carol sees accounts %v, want bob, carol and dave", accounts)
	}
	members := 0
	for _, perms := range accounts {
		if perms == chatutil.PresetMember {
			members++
		}
	}
	if members != 1 {
		t.Errorf("carol sees sets %v, want dave's effective member set on his own row", accounts)
	}

	// bob, who manages the channel, still sees crew's accounts.
	result, err = chatutil.ListMembers(chatutil.ListMembersParams{Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), ChannelID: room.ID})
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range result.Members {
		if m.GroupID == crew && (len(m.Users) != 1 || m.Users[0].ID != f.users["dave"]) {
			t.Errorf("bob sees crew as %+v, want dave in it", m)
		}
	}
}

// TestAnonymousAliasesFoldCaseAndShunUsernames checks that an alias is unique
// in its channel whatever its case, and that no alias, set or drawn, is an
// account's username in any case.
func TestAnonymousAliasesFoldCaseAndShunUsernames(t *testing.T) {
	f := newFixture(t)
	room, _ := anonymousRoom(t, f)
	alias := func(who, name string) error {
		_, err := chatutil.SetAlias(chatutil.SetAliasParams{
			Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), ChannelID: room.ID, UserID: f.users[who], Alias: name,
		})
		return err
	}
	if err := alias("dave", "Fox"); err != nil {
		t.Fatal(err)
	}
	if err := alias("carol", "fOX"); !errors.Is(err, chatutil.ErrAliasTaken) {
		t.Errorf("an alias taken in another case = %v, want ErrAliasTaken", err)
	}
	if err := alias("carol", "DAVE"); !errors.Is(err, chatutil.ErrAliasTaken) {
		t.Errorf("an alias that is a username = %v, want ErrAliasTaken", err)
	}

	// With every default alias a username, none can be drawn: a new
	// pseudonym fails rather than pass as an account.
	if _, err := f.database.Db.Exec(`WITH RECURSIVE n(i) AS (SELECT 1000 UNION ALL SELECT i + 1 FROM n WHERE i < 9999)
		INSERT INTO users (username, password_hash, recovery_phrase_hash) SELECT 'anonymous ' || i, 'h', 'r' FROM n`); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", room.ID, f.users["admin"], 0, chatutil.PresetViewer); err == nil {
		t.Error("adding a member with every default alias a username succeeded")
	}
	var made int
	if err := f.database.Db.QueryRow(`SELECT COUNT(*) FROM chat_channel_pseudonyms WHERE user_id = ?`, f.users["admin"]).Scan(&made); err != nil || made != 0 {
		t.Errorf("admin got %d pseudonyms, %v; want none", made, err)
	}
}

// TestAnonymousResultFollowsTheCallersNewSet checks that SetMember and
// RemoveMember show the members by the set the caller holds after the
// change: a manager who steps down or leaves no longer sees the accounts.
func TestAnonymousResultFollowsTheCallersNewSet(t *testing.T) {
	f := newFixture(t)
	room, _ := anonymousRoom(t, f)
	masked := func(result chatutil.ListMembersResult) bool {
		for _, m := range result.Members {
			if m.UserID > 0 {
				return false
			}
		}
		return true
	}
	if err := f.set(t, "bob", room.ID, f.users["carol"], 0, chatutil.PresetOwner); err != nil {
		t.Fatal(err)
	}
	result, err := chatutil.SetMember(chatutil.SetMemberParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("carol"),
		ChannelID: room.ID, UserID: f.users["carol"], Permissions: chatutil.PresetViewer,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !masked(result) {
		t.Errorf("carol, now a viewer, sees %+v", result.Members)
	}

	if err := f.set(t, "bob", room.ID, f.users["carol"], 0, chatutil.PresetOwner); err != nil {
		t.Fatal(err)
	}
	result, err = chatutil.RemoveMember(chatutil.RemoveMemberParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: room.ID, UserID: f.users["carol"],
	})
	if err != nil {
		t.Fatal(err)
	}
	if !masked(result) {
		t.Errorf("carol, gone, sees %+v", result.Members)
	}
}

// TestAnonymousMembersRenameOnlyThemselves checks that any member may change
// their own alias, by pseudonym or account id, and sees the members masked
// in the result, while a member without manage_members renaming anyone else,
// or a pseudonym nobody holds, gets ErrForbidden alike.
func TestAnonymousMembersRenameOnlyThemselves(t *testing.T) {
	f := newFixture(t)
	room, _ := anonymousRoom(t, f)
	ctx := context.Background()
	managed, err := chatutil.ListMembers(chatutil.ListMembersParams{Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: room.ID})
	if err != nil {
		t.Fatal(err)
	}
	var carolSelf int64
	for _, m := range managed.Members {
		if m.UserID == f.users["carol"] {
			carolSelf = m.PseudonymID
		}
	}
	rename := func(target int64, alias string) (chatutil.ListMembersResult, error) {
		return chatutil.SetAlias(chatutil.SetAliasParams{
			Ctx: ctx, Database: f.database, Principal: f.as("carol"), ChannelID: room.ID, UserID: target, Alias: alias,
		})
	}

	result, err := rename(carolSelf, "Wren")
	if err != nil {
		t.Fatalf("carol renaming herself by pseudonym = %v", err)
	}
	named := false
	for _, m := range result.Members {
		if m.UserID > 0 || len(m.Users) > 0 {
			t.Errorf("carol's result unmasks %+v", m)
		}
		named = named || (m.UserID == carolSelf && m.Name == "Wren")
	}
	if !named {
		t.Errorf("carol's result = %+v, want her as Wren", result.Members)
	}
	if _, err := rename(f.users["carol"], "Robin"); err != nil {
		t.Errorf("carol renaming herself by account id = %v", err)
	}
	for _, target := range []int64{room.SelfID, f.users["dave"], -1} {
		if _, err := rename(target, "Mask"); !errors.Is(err, chatutil.ErrForbidden) {
			t.Errorf("carol renaming %d = %v, want ErrForbidden", target, err)
		}
	}
}
