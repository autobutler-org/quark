package chatutil_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
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

// putChannelKeys publishes keys for as in an anonymous channel: a box key
// filled with fill and signer(fill)'s signing key.
func (f fixture) putChannelKeys(as string, channelID int64, fill byte) (chatutil.PutChannelKeysResult, error) {
	return chatutil.PutChannelKeys(chatutil.PutChannelKeysParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as), ChannelID: channelID,
		BoxPublicKey: sealed(fill, chatutil.PublicKeyBytes), SignPublicKey: signer(fill).Public().(ed25519.PublicKey),
	})
}

// anonGrant is a grant of version to the pseudonym `to`, signed by signer(by).
func anonGrant(by byte, channelID, version, to int64, fill byte) chatutil.GrantUpload {
	key := sealed(fill, chatutil.SealedKeyBytes)
	return chatutil.GrantUpload{
		Version: version, UserID: to, SealedKey: key,
		Signature: ed25519.Sign(signer(by), chatutil.GrantMessage(channelID, version, to, key)),
	}
}

// TestAnonymousChannelKeys checks that an anonymous channel (#2949) seals to
// and checks signatures against the keys each member published for that
// channel alone, never their account keys: a member is pending only once
// they have published, a grant or own grant signed with an account key is
// refused, and what is stored carries the channel keys. It also checks who
// may publish, that keys once published don't change, and that a new account
// identity clears them.
func TestAnonymousChannelKeys(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	f.publishKeys(t, "bob", "carol", "dave", "admin")
	created, err := chatutil.CreateChannel(chatutil.CreateChannelParams{
		Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("bob"), Name: "masks", Anonymous: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	room := created.Channel
	if err := f.set(t, "bob", room.ID, f.users["carol"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}
	const bobKey, carolKey = 'B', 'C'

	// Who may publish: a member, an admin who isn't one; not a stranger,
	// and not in a channel that isn't anonymous.
	if _, err := f.createVersion("bob", room.ID, 1); !errors.Is(err, chatutil.ErrKeysNotFound) {
		t.Errorf("creating a version before publishing channel keys = %v, want ErrKeysNotFound", err)
	}
	bob, err := f.putChannelKeys("bob", room.ID, bobKey)
	if err != nil || bob.SelfID != room.SelfID {
		t.Fatalf("bob publishes = %+v, %v; want his selfId %d", bob, err, room.SelfID)
	}
	if again, err := f.putChannelKeys("bob", room.ID, bobKey); err != nil || again.SelfID != room.SelfID {
		t.Errorf("publishing the same keys again = %+v, %v; want a no-op", again, err)
	}
	if _, err := f.putChannelKeys("bob", room.ID, 'X'); !errors.Is(err, chatutil.ErrChannelKeysSet) {
		t.Errorf("publishing other keys = %v, want ErrChannelKeysSet", err)
	}
	if admin, err := f.putChannelKeys("admin", room.ID, 'A'); err != nil || admin.SelfID >= 0 {
		t.Errorf("an admin outside the channel publishes = %+v, %v; want a pseudonym", admin, err)
	}
	if _, err := f.putChannelKeys("dave", room.ID, 'D'); !errors.Is(err, chatutil.ErrChannelNotFound) {
		t.Errorf("a stranger publishes = %v, want ErrChannelNotFound", err)
	}
	plain := f.create(t, "bob", "plain")
	if _, err := f.putChannelKeys("bob", plain.ID, bobKey); !errors.Is(err, chatutil.ErrNotAnonymous) {
		t.Errorf("publishing in a plain channel = %v, want ErrNotAnonymous", err)
	}

	// bob's own grant: the account key is refused, the channel key stored.
	ownAccount := anonGrant(f.fills["bob"], room.ID, 1, room.SelfID, 9)
	create := func(g chatutil.GrantUpload) (chatutil.CreateKeyVersionResult, error) {
		return chatutil.CreateKeyVersion(chatutil.CreateKeyVersionParams{
			Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("bob"), ChannelID: room.ID,
			Version: 1, SealedKey: g.SealedKey, Signature: g.Signature,
		})
	}
	if _, err := create(ownAccount); !errors.Is(err, chatutil.ErrGrantSignature) {
		t.Errorf("an own grant signed with the account key = %v, want ErrGrantSignature", err)
	}
	version, err := create(anonGrant(bobKey, room.ID, 1, room.SelfID, 9))
	if err != nil {
		t.Fatal(err)
	}
	bobSign := signer(bobKey).Public().(ed25519.PublicKey)
	if !bytes.Equal(version.Grant.GranterSignKey, bobSign) {
		t.Errorf("own grant's granterSignKey = %x, want bob's channel key", version.Grant.GranterSignKey)
	}
	signed, err := chatutil.SignEvent(chatutil.SignEventParams{
		Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: room.ID, EventID: version.Event.ID, Signature: sealed(1, chatutil.SignatureBytes),
	})
	if err != nil || !bytes.Equal(signed.Event.SignerSignKey, bobSign) {
		t.Errorf("signed event = %+v, %v; want bob's channel key as signerSignKey", signed.Event, err)
	}

	// carol has account keys but no channel keys, so she isn't pending.
	pending := func() []chatutil.PendingGrant {
		t.Helper()
		result, err := chatutil.ListPendingGrants(chatutil.ListPendingGrantsParams{Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: room.ID})
		if err != nil {
			t.Fatal(err)
		}
		return result.Pending
	}
	if got := pending(); len(got) != 0 {
		t.Errorf("pending before carol publishes = %+v, want none", got)
	}
	carol, err := f.putChannelKeys("carol", room.ID, carolKey)
	if err != nil {
		t.Fatal(err)
	}
	got := pending()
	if len(got) != 1 || got[0].UserID != carol.SelfID || !bytes.Equal(got[0].BoxPublicKey, sealed(carolKey, chatutil.PublicKeyBytes)) {
		t.Fatalf("pending = %+v, want carol's pseudonym with her channel box key", got)
	}
	upload := func(g chatutil.GrantUpload) (chatutil.UploadGrantsResult, error) {
		return chatutil.UploadGrants(chatutil.UploadGrantsParams{
			Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("bob"), ChannelID: room.ID, Grants: []chatutil.GrantUpload{g},
		})
	}
	if _, err := upload(anonGrant(f.fills["bob"], room.ID, 1, carol.SelfID, 7)); !errors.Is(err, chatutil.ErrGrantSignature) {
		t.Errorf("a grant signed with the account key = %v, want ErrGrantSignature", err)
	}
	stored, err := upload(anonGrant(bobKey, room.ID, 1, carol.SelfID, 7))
	if err != nil || len(stored.Grants) != 1 || !bytes.Equal(stored.Grants[0].GranterSignKey, bobSign) {
		t.Fatalf("grant = %+v, %v; want one with bob's channel key", stored, err)
	}

	// A new identity clears carol's channel keys: she must publish again,
	// and may publish different ones.
	if _, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: ctx, Queries: f.database.Queries, UserID: f.users["carol"], Keys: sampleKeys(42)}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.putChannelKeys("carol", room.ID, 'Z'); err != nil {
		t.Errorf("carol republishes after a new identity = %v, want her new keys stored", err)
	}
}
