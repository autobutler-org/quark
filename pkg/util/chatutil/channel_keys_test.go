package chatutil_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"errors"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// publishKeys gives each named account a chat identity, its bytes filled with
// the account's position so they differ.
func (f fixture) publishKeys(t *testing.T, names ...string) {
	t.Helper()
	for i, name := range names {
		if _, err := chatutil.PutKeys(chatutil.PutKeysParams{
			Ctx: context.Background(), Queries: f.database.Queries, UserID: f.users[name], Keys: sampleKeys(byte(i + 1)),
		}); err != nil {
			t.Fatal(err)
		}
		f.fills[name] = byte(i + 1)
	}
}

// sealed is a stand-in sealed key or signature of the right size.
func sealed(fill byte, n int) []byte { return bytes.Repeat([]byte{fill}, n) }

// signedGrant is a stand-in sealed key for recipient `to`, signed the way the
// app signs one, with as's published key.
func (f fixture) signedGrant(as string, channelID, version int64, to string, fill byte) chatutil.GrantUpload {
	key := sealed(fill, chatutil.SealedKeyBytes)
	return chatutil.GrantUpload{
		Version: version, UserID: f.users[to], SealedKey: key,
		Signature: ed25519.Sign(signer(f.fills[as]), chatutil.GrantMessage(channelID, version, f.users[to], key)),
	}
}

func (f fixture) createVersion(as string, channelID, version int64) (chatutil.CreateKeyVersionResult, error) {
	own := f.signedGrant(as, channelID, version, as, 9)
	return chatutil.CreateKeyVersion(chatutil.CreateKeyVersionParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as), ChannelID: channelID,
		Version: version, SealedKey: own.SealedKey, Signature: own.Signature,
	})
}

func (f fixture) grant(as string, channelID, version int64, to string, fill byte) (chatutil.UploadGrantsResult, error) {
	return chatutil.UploadGrants(chatutil.UploadGrantsParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as), ChannelID: channelID,
		Grants: []chatutil.GrantUpload{f.signedGrant(as, channelID, version, to, fill)},
	})
}

func (f fixture) channelKeys(t *testing.T, as string, channelID int64) chatutil.GetChannelKeysResult {
	t.Helper()
	result, err := chatutil.GetChannelKeys(chatutil.GetChannelKeysParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as(as), ChannelID: channelID,
	})
	if err != nil {
		t.Fatalf("GetChannelKeys as %s: %v", as, err)
	}
	return result
}

// pendingFor names who the caller could fill each version for.
func (f fixture) pendingFor(t *testing.T, as string, channelID int64) map[int64][]string {
	t.Helper()
	result, err := chatutil.ListPendingGrants(chatutil.ListPendingGrantsParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as(as), ChannelID: channelID,
	})
	if err != nil {
		t.Fatalf("ListPendingGrants as %s: %v", as, err)
	}
	names := map[int64][]string{}
	for _, p := range result.Pending {
		for name, id := range f.users {
			if id == p.UserID {
				names[p.Version] = append(names[p.Version], name)
			}
		}
		if len(p.BoxPublicKey) != chatutil.PublicKeyBytes {
			t.Errorf("pending %+v has no box key", p)
		}
	}
	for v := range names {
		slices.Sort(names[v])
	}
	return names
}

func TestPendingSetCoversDirectGroupAndEveryone(t *testing.T) {
	f := newFixture(t)
	// admin publishes no keys, so it is never pending.
	f.publishKeys(t, "bob", "carol", "dave")
	team := f.group(t, "team", "carol")
	channel := f.create(t, "bob", "design")
	if err := f.set(t, "bob", channel.ID, 0, team, chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}
	if got := f.channelKeys(t, "bob", channel.ID); got.CurrentVersion != 0 || len(got.Grants) != 0 {
		t.Fatalf("a new channel has keys: %+v", got)
	}
	if _, err := f.createVersion("bob", channel.ID, 1); err != nil {
		t.Fatal(err)
	}
	if got := f.pendingFor(t, "bob", channel.ID); !slices.Equal(got[1], []string{"carol"}) {
		t.Errorf("group member pending = %v, want carol", got)
	}
	if err := f.set(t, "bob", channel.ID, f.users["dave"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}
	if got := f.pendingFor(t, "bob", channel.ID); !slices.Equal(got[1], []string{"carol", "dave"}) {
		t.Errorf("direct member pending = %v, want carol and dave", got)
	}
	// carol holds nothing, so she has nothing to fill.
	if got := f.pendingFor(t, "carol", channel.ID); len(got) != 0 {
		t.Errorf("carol, holding no key, may fill %v", got)
	}

	general := f.general(t)
	if _, err := f.createVersion("bob", general.ID, 1); err != nil {
		t.Fatal(err)
	}
	if got := f.pendingFor(t, "bob", general.ID); !slices.Equal(got[1], []string{"carol", "dave"}) {
		t.Errorf("everyone pending = %v, want carol and dave", got)
	}
	f.publishKeys(t, "admin")
	if got := f.pendingFor(t, "bob", general.ID); !slices.Equal(got[1], []string{"admin", "carol", "dave"}) {
		t.Errorf("after admin published keys, pending = %v", got)
	}

	// A new member gets every version, so they can read the history. admin
	// holding version 1 and then leaving is what lets bob rotate.
	if err := f.set(t, "bob", channel.ID, f.users["admin"], 0, chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}
	if _, err := f.grant("bob", channel.ID, 1, "admin", 1); err != nil {
		t.Fatal(err)
	}
	if err := f.remove("bob", channel.ID, f.users["admin"], 0); err != nil {
		t.Fatal(err)
	}
	if _, err := f.createVersion("bob", channel.ID, 2); err != nil {
		t.Fatal(err)
	}
	if got := f.pendingFor(t, "bob", channel.ID); !slices.Equal(got[1], []string{"carol", "dave"}) || !slices.Equal(got[2], []string{"carol", "dave"}) {
		t.Errorf("pending across versions = %v", got)
	}
}

// TestGroupJoinIsAnnouncedWithoutOpeningSettings adds an account to a group
// the way the admin route does, which publishes only access_changed, and
// checks the watcher tells the key holder to fill the newcomer's grants.
func TestGroupJoinIsAnnouncedWithoutOpeningSettings(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "admin", "bob", "carol", "dave")
	team := f.group(t, "team", "carol")
	channel := f.create(t, "bob", "design")
	for _, err := range []error{
		f.set(t, "bob", channel.ID, 0, team, chatutil.PresetViewer),
		f.set(t, "bob", channel.ID, f.users["admin"], 0, chatutil.PresetViewer),
	} {
		if err != nil {
			t.Fatal(err)
		}
	}
	for v := int64(1); v <= 2; v++ {
		if _, err := f.createVersion("bob", channel.ID, v); err != nil {
			t.Fatal(err)
		}
		if _, err := f.grant("bob", channel.ID, v, "carol", 1); err != nil {
			t.Fatal(err)
		}
		// admin holding version 1 and leaving is what lets bob rotate.
		if v == 1 {
			if _, err := f.grant("bob", channel.ID, v, "admin", 1); err != nil {
				t.Fatal(err)
			}
			if err := f.remove("bob", channel.ID, f.users["admin"], 0); err != nil {
				t.Fatal(err)
			}
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go chatutil.WatchKeyNeeds(chatutil.WatchKeyNeedsParams{Ctx: ctx, Database: f.database, EventBus: f.bus})
	events, unsub := f.bus.Subscribe("key-needs-test")
	defer unsub()

	if _, err := f.database.Queries.AddGroupMember(ctx, db.AddGroupMemberParams{GroupID: team, UserID: f.users["dave"]}); err != nil {
		t.Fatal(err)
	}
	deadline := time.After(5 * time.Second)
	tick := time.NewTicker(20 * time.Millisecond)
	defer tick.Stop()
	for heard := false; !heard; {
		select {
		case <-deadline:
			t.Fatal("no chat_key_needed after dave joined the group")
		case <-tick.C:
			// The watcher subscribes in its own goroutine, so keep telling it
			// until it is listening.
			f.bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
		case evt := <-events:
			changed, ok := evt.Data.(eventbus.ChatChannelChanged)
			if evt.Kind != eventbus.EventChatKeyNeeded || !ok || changed.ChannelID != channel.ID {
				continue
			}
			if !slices.Contains(changed.Audience, f.users["bob"]) || slices.Contains(changed.Audience, f.users["dave"]) {
				t.Errorf("chat_key_needed audience = %v, want the holders", changed.Audience)
			}
			heard = true
		}
	}
	if got := f.pendingFor(t, "carol", channel.ID); !slices.Equal(got[1], []string{"dave"}) || !slices.Equal(got[2], []string{"dave"}) {
		t.Errorf("dave's pending grants = %v, want both versions", got)
	}
}

// keyNeeded waits briefly for chat_key_needed on channelID and returns its
// audience, or nil when none came.
func keyNeeded(events <-chan eventbus.Event, channelID int64) []int64 {
	deadline := time.After(time.Second)
	for {
		select {
		case <-deadline:
			return nil
		case evt := <-events:
			changed, ok := evt.Data.(eventbus.ChatChannelChanged)
			if evt.Kind == eventbus.EventChatKeyNeeded && ok && changed.ChannelID == channelID {
				return changed.Audience
			}
		}
	}
}

// TestMemberChangeAsksHoldersAtOnce changes a keyed channel's members with no
// watcher running (#2624): SetMember and RemoveMember themselves must tell the
// key holders to fill or rotate, not leave it to WatchKeyNeeds catching up.
func TestMemberChangeAsksHoldersAtOnce(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol")
	channel := f.create(t, "bob", "design")
	if _, err := f.createVersion("bob", channel.ID, 1); err != nil {
		t.Fatal(err)
	}
	events, unsub := f.bus.Subscribe("member-change-test")
	defer unsub()

	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}
	if got := keyNeeded(events, channel.ID); !slices.Equal(got, []int64{f.users["bob"]}) {
		t.Errorf("chat_key_needed after adding carol = %v, want bob", got)
	}
	if got := f.pendingFor(t, "bob", channel.ID); !slices.Equal(got[1], []string{"carol"}) {
		t.Errorf("bob's pending grants = %v, want carol's", got)
	}

	if _, err := f.grant("bob", channel.ID, 1, "carol", 1); err != nil {
		t.Fatal(err)
	}
	if err := f.remove("bob", channel.ID, f.users["carol"], 0); err != nil {
		t.Fatal(err)
	}
	if got := keyNeeded(events, channel.ID); !slices.Equal(got, []int64{f.users["bob"]}) {
		t.Errorf("chat_key_needed after removing carol = %v, want bob to rotate", got)
	}
}

func TestFirstGrantWins(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol", "dave")
	general := f.general(t)
	if _, err := f.createVersion("bob", general.ID, 1); err != nil {
		t.Fatal(err)
	}
	if _, err := f.grant("bob", general.ID, 1, "dave", 1); err != nil {
		t.Fatal(err)
	}
	first, err := f.grant("bob", general.ID, 1, "carol", 2)
	if err != nil {
		t.Fatal(err)
	}
	second, err := f.grant("dave", general.ID, 1, "carol", 3)
	if err != nil {
		t.Fatal(err)
	}
	if second.Grants[0].GrantedBy != f.users["bob"] || !bytes.Equal(second.Grants[0].SealedKey, first.Grants[0].SealedKey) {
		t.Errorf("the later grant replaced the first: %+v", second.Grants[0])
	}
	mine := f.channelKeys(t, "carol", general.ID)
	if len(mine.Grants) != 1 || mine.Grants[0].GrantedBy != f.users["bob"] || !bytes.Equal(mine.Grants[0].GranterSignKey, sampleKeys(1).SignPublicKey) {
		t.Errorf("carol's grants = %+v", mine.Grants)
	}
}

func TestGrantsAreForMembersOnly(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "admin", "bob", "carol", "dave")
	channel := f.create(t, "bob", "secret")
	if err := f.set(t, "bob", channel.ID, f.users["dave"], 0, chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}
	if _, err := f.createVersion("bob", channel.ID, 1); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	for _, outsider := range []string{"carol", "admin"} {
		p := f.as(outsider)
		_, err1 := chatutil.GetChannelKeys(chatutil.GetChannelKeysParams{Ctx: ctx, Database: f.database, Principal: p, ChannelID: channel.ID})
		_, err2 := chatutil.ListPendingGrants(chatutil.ListPendingGrantsParams{Ctx: ctx, Database: f.database, Principal: p, ChannelID: channel.ID})
		_, err3 := f.grant(outsider, channel.ID, 1, "dave", 1)
		_, err4 := f.createVersion(outsider, channel.ID, 2)
		_, err5 := chatutil.ListEvents(chatutil.ListEventsParams{Ctx: ctx, Database: f.database, Principal: p, ChannelID: channel.ID})
		for i, err := range []error{err1, err2, err3, err4, err5} {
			if !errors.Is(err, chatutil.ErrChannelNotFound) {
				t.Errorf("%s, call %d: %v, want ErrChannelNotFound", outsider, i+1, err)
			}
		}
	}
	if _, err := f.grant("dave", channel.ID, 1, "bob", 1); !errors.Is(err, chatutil.ErrNotHolder) {
		t.Errorf("dave, holding nothing, granted: %v", err)
	}
	if _, err := f.grant("bob", channel.ID, 1, "carol", 1); !errors.Is(err, chatutil.ErrInvalidGrant) {
		t.Errorf("bob granted carol, a non-member: %v", err)
	}
	if _, err := chatutil.UploadGrants(chatutil.UploadGrantsParams{
		Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: channel.ID,
		Grants: []chatutil.GrantUpload{{Version: 1, UserID: f.users["dave"], SealedKey: sealed(1, 10), Signature: sealed(1, chatutil.SignatureBytes)}},
	}); !errors.Is(err, chatutil.ErrInvalidGrant) {
		t.Errorf("a short sealed key was accepted: %v", err)
	}
	if _, err := f.createVersion("bob", channel.ID, 3); !errors.Is(err, chatutil.ErrVersionConflict) {
		t.Errorf("skipping a version: %v, want ErrVersionConflict", err)
	}
	if _, err := f.createVersion("dave", channel.ID, 1); !errors.Is(err, chatutil.ErrVersionConflict) {
		t.Errorf("recreating version 1: %v, want ErrVersionConflict", err)
	}
}

func TestRemovalNeedsRotation(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol", "dave")
	team := f.group(t, "team", "dave")
	channel := f.create(t, "bob", "design")
	for _, err := range []error{
		f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PresetMember),
		f.set(t, "bob", channel.ID, 0, team, chatutil.PresetViewer),
	} {
		if err != nil {
			t.Fatal(err)
		}
	}
	if _, err := f.createVersion("bob", channel.ID, 1); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"carol", "dave"} {
		if _, err := f.grant("bob", channel.ID, 1, name, 1); err != nil {
			t.Fatal(err)
		}
	}
	if f.channelKeys(t, "bob", channel.ID).RotationNeeded {
		t.Fatal("rotation needed before anyone left")
	}
	if _, err := f.createVersion("carol", channel.ID, 2); !errors.Is(err, chatutil.ErrRotationNotNeeded) {
		t.Errorf("rotating before anyone left: %v, want ErrRotationNotNeeded", err)
	}

	// carol leaves.
	if err := f.remove("carol", channel.ID, f.users["carol"], 0); err != nil {
		t.Fatal(err)
	}
	if !f.channelKeys(t, "bob", channel.ID).RotationNeeded {
		t.Fatal("no rotation after carol left")
	}
	if _, err := chatutil.GetChannelKeys(chatutil.GetChannelKeysParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channel.ID}); !errors.Is(err, chatutil.ErrChannelNotFound) {
		t.Errorf("carol still gets grants after leaving: %v", err)
	}
	if _, err := f.createVersion("dave", channel.ID, 2); err != nil {
		t.Fatal(err)
	}
	keys := f.channelKeys(t, "dave", channel.ID)
	if keys.RotationNeeded || keys.CurrentVersion != 2 {
		t.Errorf("after rotating: %+v", keys)
	}
	if got := f.pendingFor(t, "dave", channel.ID); !slices.Equal(got[2], []string{"bob"}) {
		t.Errorf("after rotating, dave can fill %v, want bob for version 2", got)
	}
	if _, err := f.grant("dave", channel.ID, 2, "bob", 2); err != nil {
		t.Fatal(err)
	}

	// Leaving a group, and deletion, are removals too.
	if _, err := f.database.Queries.RemoveGroupMember(context.Background(), db.RemoveGroupMemberParams{GroupID: team, UserID: f.users["dave"]}); err != nil {
		t.Fatal(err)
	}
	if !f.channelKeys(t, "bob", channel.ID).RotationNeeded {
		t.Error("no rotation after dave left the group")
	}
	if _, err := f.createVersion("bob", channel.ID, 3); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}
	if _, err := f.grant("bob", channel.ID, 3, "carol", 3); err != nil {
		t.Fatal(err)
	}
	if _, err := authutil.DeleteUser(context.Background(), authutil.DeleteUserParams{Database: f.database, ActorUserID: f.users["admin"], Username: "carol"}); err != nil {
		t.Fatal(err)
	}
	if !f.channelKeys(t, "bob", channel.ID).RotationNeeded {
		t.Error("no rotation after carol's account was deleted")
	}
}

// TestOnlyReadMessagesMapsToTheKey gives dave a manage-only set, a delegated
// manager: never pending and never served a grant. Demoting carol from
// Member to manage_members alone rotates the key; changing only
// send_messages or manage_channel does not.
func TestOnlyReadMessagesMapsToTheKey(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol", "dave")
	channel := f.create(t, "bob", "design")
	for name, perms := range map[string]chatutil.Perms{"carol": chatutil.PresetMember, "dave": chatutil.PermManageMembers} {
		if err := f.set(t, "bob", channel.ID, f.users[name], 0, perms); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := f.createVersion("bob", channel.ID, 1); err != nil {
		t.Fatal(err)
	}
	if got := f.pendingFor(t, "bob", channel.ID); !slices.Equal(got[1], []string{"carol"}) {
		t.Errorf("pending = %v, want carol and not the delegated manager", got)
	}
	if _, err := chatutil.GetChannelKeys(chatutil.GetChannelKeysParams{Ctx: context.Background(), Database: f.database, Principal: f.as("dave"), ChannelID: channel.ID}); !errors.Is(err, chatutil.ErrChannelNotFound) {
		t.Errorf("the delegated manager fetching grants = %v, want ErrChannelNotFound", err)
	}
	if _, err := f.grant("bob", channel.ID, 1, "dave", 1); !errors.Is(err, chatutil.ErrInvalidGrant) {
		t.Errorf("granting the delegated manager = %v, want ErrInvalidGrant", err)
	}
	if _, err := f.grant("bob", channel.ID, 1, "carol", 1); err != nil {
		t.Fatal(err)
	}

	// Bits other than read_messages are the server's alone: no rotation.
	for _, perms := range []chatutil.Perms{chatutil.PresetViewer, chatutil.PresetViewer | chatutil.PermManageChannel, chatutil.PresetMember} {
		if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, perms); err != nil {
			t.Fatal(err)
		}
		if f.channelKeys(t, "bob", channel.ID).RotationNeeded {
			t.Errorf("rotation needed after carol went to %v", perms)
		}
	}
	// Losing read_messages while keeping a bit is a removal from the key set.
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PermManageMembers); err != nil {
		t.Fatal(err)
	}
	if !f.channelKeys(t, "bob", channel.ID).RotationNeeded {
		t.Error("no rotation after carol lost read_messages")
	}
	if got := f.pendingFor(t, "bob", channel.ID); len(got) != 0 {
		t.Errorf("pending after the demotion = %v, want none", got)
	}
	// Gaining it back makes her pending again for every version.
	if _, err := f.createVersion("bob", channel.ID, 2); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}
	if got := f.pendingFor(t, "bob", channel.ID); !slices.Equal(got[2], []string{"carol"}) {
		t.Errorf("pending after carol regained read_messages = %v", got)
	}
}

func TestNewBoxKeyDropsGrants(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol")
	general := f.general(t)
	if _, err := f.createVersion("bob", general.ID, 1); err != nil {
		t.Fatal(err)
	}
	if _, err := f.grant("bob", general.ID, 1, "carol", 1); err != nil {
		t.Fatal(err)
	}
	// Re-uploading the same identity keeps the grant.
	f.publishKeys(t, "bob", "carol")
	if got := f.channelKeys(t, "carol", general.ID).Grants; len(got) != 1 {
		t.Fatalf("same keys dropped carol's grant: %+v", got)
	}
	if _, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: context.Background(), Queries: f.database.Queries, UserID: f.users["carol"], Keys: sampleKeys(7)}); err != nil {
		t.Fatal(err)
	}
	if got := f.channelKeys(t, "carol", general.ID).Grants; len(got) != 0 {
		t.Errorf("carol's grant sealed to her old key survived: %+v", got)
	}
	if got := f.pendingFor(t, "bob", general.ID); !slices.Equal(got[1], []string{"carol"}) {
		t.Errorf("carol isn't pending again: %v", got)
	}
}

func TestEventsAreRecordedAndSignedOnce(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol")
	channel := f.create(t, "bob", "design")
	added, err := chatutil.SetMember(chatutil.SetMemberParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"),
		ChannelID: channel.ID, UserID: f.users["carol"], Permissions: chatutil.PresetMember,
	})
	if err != nil {
		t.Fatal(err)
	}
	event := added.Event
	if event == nil || event.Kind != chatutil.EventMemberSet || event.ActorID != f.users["bob"] ||
		event.Payload != `{"userId":`+strconv.FormatInt(f.users["carol"], 10)+`,"name":"carol","permissions":["read_messages","send_messages","add_reactions"]}` {
		t.Fatalf("member_set event = %+v", event)
	}
	created, err := f.createVersion("carol", channel.ID, 1)
	if err != nil {
		t.Fatal(err)
	}
	if created.Event.Kind != chatutil.EventKeyCreated || created.Event.Payload != `{"version":1}` {
		t.Errorf("key_created event = %+v", created.Event)
	}

	sign := func(as string, id int64) (chatutil.SignEventResult, error) {
		return chatutil.SignEvent(chatutil.SignEventParams{
			Ctx: context.Background(), Database: f.database, Principal: f.as(as),
			ChannelID: channel.ID, EventID: id, Signature: sealed(5, chatutil.SignatureBytes),
		})
	}
	if _, err := sign("carol", event.ID); !errors.Is(err, chatutil.ErrEventNotFound) {
		t.Errorf("carol signed bob's event: %v", err)
	}
	signed, err := sign("bob", event.ID)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(signed.Event.SignerSignKey, sampleKeys(1).SignPublicKey) {
		t.Errorf("signed event = %+v", signed.Event)
	}
	if _, err := sign("bob", event.ID); !errors.Is(err, chatutil.ErrEventSigned) {
		t.Errorf("signing twice: %v", err)
	}

	listed, err := chatutil.ListEvents(chatutil.ListEventsParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channel.ID})
	if err != nil {
		t.Fatal(err)
	}
	if len(listed.Events) != 2 || listed.Events[0].Signature == nil || listed.Events[1].Signature != nil {
		t.Errorf("events = %+v", listed.Events)
	}
	after, err := chatutil.ListEvents(chatutil.ListEventsParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channel.ID, After: event.ID})
	if err != nil || len(after.Events) != 1 || after.Events[0].Kind != chatutil.EventKeyCreated {
		t.Errorf("events after %d = %+v, %v", event.ID, after.Events, err)
	}

	// carol leaves, then signs her leaving from outside the channel.
	left, err := chatutil.RemoveMember(chatutil.RemoveMemberParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("carol"),
		ChannelID: channel.ID, UserID: f.users["carol"],
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := sign("carol", left.Event.ID); err != nil {
		t.Errorf("carol signing her own leaving after it: %v", err)
	}
	if _, err := sign("dave", left.Event.ID); err == nil {
		t.Error("dave, never a member, signed carol's event")
	}
}

// TestGrantMessageVector pins the grant transcript and its signature to a
// fixed vector: seed 32 bytes of 0x42, channel 7, version 2, recipient 42 and
// a sealed key of 80 bytes of 0xab. The message was cross-checked against
// an independent Python BLAKE2b and struct packing; the signature is Go's Ed25519
// over it, which is deterministic from the seed, as libsodium's is.
func TestGrantMessageVector(t *testing.T) {
	const (
		wantPublic  = "2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
		wantMessage = "717561726b2d636861742d6772616e742d7631000000000000000007000000000000000200000000000000" +
			"2afc447c9d8c582d5538c677983efb708ea39840d09f695a7e1bc13bce1c27f9d3"
		wantSignature = "5d56361c47c8464f77021ed3b14c8bee9c489cc5fc7fdb4b82a5cb2f2f4bcc1c" +
			"a53db7597dc8e50ad58bd80590452b7a778587db86dff8316138dc37ce1b8b0d"
	)
	key := signer(0x42)
	message := chatutil.GrantMessage(7, 2, 42, sealed(0xab, chatutil.SealedKeyBytes))
	if got := hex.EncodeToString(key.Public().(ed25519.PublicKey)); got != wantPublic {
		t.Errorf("public key = %s", got)
	}
	if got := hex.EncodeToString(message); got != wantMessage {
		t.Errorf("message = %s", got)
	}
	signature, _ := hex.DecodeString(wantSignature)
	if !ed25519.Verify(key.Public().(ed25519.PublicKey), message, signature) {
		t.Error("the fixed signature doesn't verify")
	}
}

// TestGrantSignaturesAreVerified refuses grants the caller didn't sign over
// the exact transcript, before anything is stored (#2486).
func TestGrantSignaturesAreVerified(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol", "dave")
	general := f.general(t)
	ctx := context.Background()

	forged := f.signedGrant("carol", general.ID, 1, "bob", 9)
	if _, err := chatutil.CreateKeyVersion(chatutil.CreateKeyVersionParams{
		Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: general.ID,
		Version: 1, SealedKey: forged.SealedKey, Signature: forged.Signature,
	}); !errors.Is(err, chatutil.ErrGrantSignature) {
		t.Fatalf("a version with carol's signature on bob's grant: %v, want ErrGrantSignature", err)
	}
	if _, err := f.createVersion("bob", general.ID, 1); err != nil {
		t.Fatal(err)
	}
	// relabel keeps a grant's sealed key and signature but addresses it to
	// carol for version 1, as a replay would.
	relabel := func(g chatutil.GrantUpload) chatutil.GrantUpload {
		g.UserID, g.Version = f.users["carol"], 1
		return g
	}
	wrong := map[string]chatutil.GrantUpload{
		"signed by someone else": f.signedGrant("carol", general.ID, 1, "carol", 1),
		"signed for dave":        relabel(f.signedGrant("bob", general.ID, 1, "dave", 1)),
		"signed for version 2":   relabel(f.signedGrant("bob", general.ID, 2, "carol", 1)),
		"signed for channel 999": f.signedGrant("bob", 999, 1, "carol", 1),
	}
	tampered := f.signedGrant("bob", general.ID, 1, "carol", 1)
	tampered.SealedKey = sealed(2, chatutil.SealedKeyBytes)
	wrong["another sealed key"] = tampered
	for name, g := range wrong {
		if _, err := chatutil.UploadGrants(chatutil.UploadGrantsParams{
			Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: general.ID, Grants: []chatutil.GrantUpload{g},
		}); !errors.Is(err, chatutil.ErrGrantSignature) {
			t.Errorf("%s: %v, want ErrGrantSignature", name, err)
		}
	}
	if got := f.channelKeys(t, "carol", general.ID).Grants; len(got) != 0 {
		t.Errorf("a bad grant was stored: %+v", got)
	}
	if _, err := f.grant("bob", general.ID, 1, "carol", 1); err != nil {
		t.Errorf("a well-signed grant: %v", err)
	}
}

// TestRecipientRejectsGrant lets carol drop a grant she can't open, which
// makes her pending again and asks the holders to refill it (#2486).
func TestRecipientRejectsGrant(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol", "dave")
	general := f.general(t)
	if _, err := f.createVersion("bob", general.ID, 1); err != nil {
		t.Fatal(err)
	}
	if _, err := f.grant("dave", general.ID, 1, "carol", 1); !errors.Is(err, chatutil.ErrNotHolder) {
		t.Fatalf("dave granted without holding: %v", err)
	}
	if _, err := f.grant("bob", general.ID, 1, "dave", 1); err != nil {
		t.Fatal(err)
	}
	// dave squats carol's grant with a signed but useless sealed key.
	if _, err := f.grant("dave", general.ID, 1, "carol", 7); err != nil {
		t.Fatal(err)
	}
	reject := func(as string) error {
		_, err := chatutil.RejectGrant(chatutil.RejectGrantParams{
			Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as), ChannelID: general.ID, Version: 1,
		})
		return err
	}
	events, unsub := f.bus.Subscribe("reject-grant-test")
	defer unsub()
	if err := reject("carol"); err != nil {
		t.Fatal(err)
	}
	if got := f.channelKeys(t, "carol", general.ID).Grants; len(got) != 0 {
		t.Errorf("carol's rejected grant is still there: %+v", got)
	}
	if got := f.pendingFor(t, "bob", general.ID); !slices.Equal(got[1], []string{"carol"}) {
		t.Errorf("pending after carol rejected = %v, want carol", got)
	}
	heard := false
	for !heard {
		select {
		case evt := <-events:
			changed, ok := evt.Data.(eventbus.ChatChannelChanged)
			heard = evt.Kind == eventbus.EventChatKeyNeeded && ok && changed.ChannelID == general.ID &&
				slices.Contains(changed.Audience, f.users["bob"])
		case <-time.After(time.Second):
			t.Fatal("no chat_key_needed to bob after the rejection")
		}
	}
	if err := reject("carol"); !errors.Is(err, chatutil.ErrGrantNotFound) {
		t.Errorf("rejecting twice: %v, want ErrGrantNotFound", err)
	}
	if err := reject("admin"); !errors.Is(err, chatutil.ErrGrantNotFound) {
		t.Errorf("admin, holding nothing: %v, want ErrGrantNotFound", err)
	}
	if _, err := f.grant("bob", general.ID, 1, "carol", 1); err != nil {
		t.Errorf("refilling carol after she rejected: %v", err)
	}
	if got := f.channelKeys(t, "carol", general.ID).Grants; len(got) != 1 || got[0].GrantedBy != f.users["bob"] {
		t.Errorf("carol's refilled grants = %+v", got)
	}
}
