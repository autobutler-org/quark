package chatutil_test

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func (f fixture) dm(t *testing.T, as string, with ...string) chatutil.OpenDirectMessageResult {
	t.Helper()
	result, err := f.openDM(as, with...)
	if err != nil {
		t.Fatalf("OpenDirectMessage as %s with %v: %v", as, with, err)
	}
	return result
}

func (f fixture) openDM(as string, with ...string) (chatutil.OpenDirectMessageResult, error) {
	ids := []int64{}
	for _, name := range with {
		ids = append(ids, f.users[name])
	}
	return chatutil.OpenDirectMessage(chatutil.OpenDirectMessageParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as), UserIDs: ids,
	})
}

// TestDirectMessageIsReusedForTheSameSet opens the same conversation from
// either side and in any order, and a different one for a different set.
func TestDirectMessageIsReusedForTheSameSet(t *testing.T) {
	f := newFixture(t)
	first := f.dm(t, "bob", "carol")
	if !first.Created || first.Channel.Kind != chatutil.KindDirect || first.Channel.Name != "" ||
		first.Channel.Permissions != chatutil.PresetMember || len(first.Channel.Members) != 2 {
		t.Fatalf("first open = %+v, want a new dm with bob and carol at the Member set", first)
	}
	for _, again := range []chatutil.OpenDirectMessageResult{
		f.dm(t, "carol", "bob"),
		f.dm(t, "bob", "carol", "carol", "bob"),
	} {
		if again.Created || again.Channel.ID != first.Channel.ID {
			t.Errorf("reopen = %+v, want channel %d, not created", again, first.Channel.ID)
		}
	}
	group := f.dm(t, "bob", "carol", "dave")
	if !group.Created || group.Channel.ID == first.Channel.ID {
		t.Errorf("adding dave = %+v, want a new direct message", group)
	}

	listed, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol")})
	if err != nil {
		t.Fatal(err)
	}
	dms := 0
	for _, channel := range listed.Channels {
		if channel.Kind == chatutil.KindDirect {
			dms++
			if len(channel.Members) < 2 {
				t.Errorf("listed dm %d has members %+v", channel.ID, channel.Members)
			}
		}
	}
	if dms != 2 {
		t.Errorf("carol lists %d direct messages, want 2", dms)
	}
}

// TestDirectMessageRefusesBadSets turns away an empty set, the caller alone,
// a missing account and too many people.
func TestDirectMessageRefusesBadSets(t *testing.T) {
	f := newFixture(t)
	if _, err := f.openDM("bob"); !errors.Is(err, chatutil.ErrDirectMessageMembers) {
		t.Errorf("no one = %v, want ErrDirectMessageMembers", err)
	}
	if _, err := f.openDM("bob", "bob"); !errors.Is(err, chatutil.ErrDirectMessageMembers) {
		t.Errorf("only self = %v, want ErrDirectMessageMembers", err)
	}
	if _, err := chatutil.OpenDirectMessage(chatutil.OpenDirectMessageParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), UserIDs: []int64{9999},
	}); !errors.Is(err, accessutil.ErrPrincipalNotFound) {
		t.Errorf("missing account = %v, want ErrPrincipalNotFound", err)
	}
	many := make([]int64, chatutil.MaxDirectMessageMembers)
	for i := range many {
		many[i] = int64(1000 + i)
	}
	if _, err := chatutil.OpenDirectMessage(chatutil.OpenDirectMessageParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), UserIDs: many,
	}); !errors.Is(err, chatutil.ErrDirectMessageMembers) {
		t.Errorf("too many = %v, want ErrDirectMessageMembers", err)
	}
}

// TestDirectMessageIsHiddenFromANonMemberAdmin walks every path an admin
// has to a channel and finds no trace of a direct message they are not in
// (#2423).
func TestDirectMessageIsHiddenFromANonMemberAdmin(t *testing.T) {
	f := newFixture(t)
	heard, stop := f.bus.Subscribe("test")
	defer stop()
	dm := f.dm(t, "bob", "carol").Channel
	ctx := context.Background()
	admin := f.as("admin")

	all, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: ctx, Database: f.database, Principal: admin, All: true})
	if err != nil {
		t.Fatal(err)
	}
	for _, channel := range all.Channels {
		if channel.ID == dm.ID {
			t.Fatalf("admin's every-channel list holds the direct message")
		}
	}

	name := "spy"
	checks := map[string]error{}
	_, checks["UpdateChannel"] = chatutil.UpdateChannel(chatutil.UpdateChannelParams{Ctx: ctx, Database: f.database, Principal: admin, ChannelID: dm.ID, Name: &name})
	_, checks["DeleteChannel"] = chatutil.DeleteChannel(chatutil.DeleteChannelParams{Ctx: ctx, Database: f.database, Principal: admin, ChannelID: dm.ID})
	_, checks["ListMembers"] = chatutil.ListMembers(chatutil.ListMembersParams{Ctx: ctx, Database: f.database, Principal: admin, ChannelID: dm.ID})
	checks["SetMember"] = f.set(t, "admin", dm.ID, f.users["admin"], 0, chatutil.PresetMember)
	checks["RemoveMember"] = f.remove("admin", dm.ID, f.users["carol"], 0)
	_, checks["GetChannelKeys"] = chatutil.GetChannelKeys(chatutil.GetChannelKeysParams{Ctx: ctx, Database: f.database, Principal: admin, ChannelID: dm.ID})
	_, checks["ListPendingGrants"] = chatutil.ListPendingGrants(chatutil.ListPendingGrantsParams{Ctx: ctx, Database: f.database, Principal: admin, ChannelID: dm.ID})
	_, checks["ListEvents"] = chatutil.ListEvents(chatutil.ListEventsParams{Ctx: ctx, Database: f.database, Principal: admin, ChannelID: dm.ID})
	_, checks["ListMessages"] = chatutil.ListMessages(chatutil.ListMessagesParams{Ctx: ctx, Database: f.database, Principal: admin, ChannelID: dm.ID})
	_, checks["MarkRead"] = chatutil.MarkRead(chatutil.MarkReadParams{Ctx: ctx, Database: f.database, Principal: admin, ChannelID: dm.ID, MessageID: 1})
	for name, err := range checks {
		if !errors.Is(err, chatutil.ErrChannelNotFound) {
			t.Errorf("%s as a non-member admin = %v, want ErrChannelNotFound", name, err)
		}
	}
	if f.resolve(t, "carol", dm.ID) != chatutil.PresetMember {
		t.Errorf("carol lost her place in the direct message")
	}

	// The open told bob and carol, marked so an admin's stream drops it.
	adminAccess, err := accessutil.Load(accessutil.LoadParams{Ctx: ctx, Database: f.database, Principal: admin})
	if err != nil {
		t.Fatal(err)
	}
	evt := <-heard
	if changed, ok := evt.Data.(eventbus.ChatChannelChanged); !ok || evt.Kind != eventbus.EventChatChannelChanged ||
		changed.ChannelID != dm.ID || !changed.Direct || len(changed.Audience) != 2 {
		t.Fatalf("event = %+v, want a direct chat_channel_changed for bob and carol", evt)
	}
	if accessutil.FilterEvent(accessutil.FilterEventParams{Access: adminAccess.Access, Event: evt}).Deliver {
		t.Errorf("the admin's event stream delivers the direct message's event")
	}
}

// TestDirectMessageKeepsItsPeople refuses every change to a direct
// message's name or members to the people in it, an admin among them.
func TestDirectMessageKeepsItsPeople(t *testing.T) {
	f := newFixture(t)
	dm := f.dm(t, "admin", "bob").Channel
	ctx := context.Background()
	name := "renamed"
	for _, as := range []string{"admin", "bob"} {
		checks := map[string]error{}
		_, checks["UpdateChannel"] = chatutil.UpdateChannel(chatutil.UpdateChannelParams{Ctx: ctx, Database: f.database, Principal: f.as(as), ChannelID: dm.ID, Name: &name})
		_, checks["DeleteChannel"] = chatutil.DeleteChannel(chatutil.DeleteChannelParams{Ctx: ctx, Database: f.database, Principal: f.as(as), ChannelID: dm.ID})
		checks["SetMember"] = f.set(t, as, dm.ID, f.users["carol"], 0, chatutil.PresetMember)
		checks["SetMember everyone"] = f.set(t, as, dm.ID, 0, f.everyone, chatutil.PresetViewer)
		checks["RemoveMember leave"] = f.remove(as, dm.ID, f.users[as], 0)
		for name, err := range checks {
			if !errors.Is(err, chatutil.ErrDirectMessage) {
				t.Errorf("%s as %s = %v, want ErrDirectMessage", name, as, err)
			}
		}
		if _, err := chatutil.ListMembers(chatutil.ListMembersParams{Ctx: ctx, Database: f.database, Principal: f.as(as), ChannelID: dm.ID}); err != nil {
			t.Errorf("ListMembers as %s = %v", as, err)
		}
	}
	if len(f.dm(t, "bob", "admin").Channel.Members) != 2 {
		t.Errorf("the direct message's people changed")
	}
}

// TestDirectMessageOutlivesADeletedAccount keeps the conversation for the
// people left in it, and a new one between them is a fresh start.
func TestDirectMessageOutlivesADeletedAccount(t *testing.T) {
	f := newFixture(t)
	group := f.dm(t, "bob", "carol", "dave").Channel
	pair := f.dm(t, "bob", "carol").Channel
	if err := f.database.Queries.DeleteUser(context.Background(), f.users["dave"]); err != nil {
		t.Fatal(err)
	}
	if f.resolve(t, "bob", group.ID) != chatutil.PresetMember {
		t.Errorf("bob lost the group conversation when dave was deleted")
	}
	if again := f.dm(t, "carol", "bob"); again.Channel.ID != pair.ID {
		t.Errorf("bob and carol reopen %d, want their own conversation %d", again.Channel.ID, pair.ID)
	}
}

// directMessageRaceRounds is how many times the pair of opens is fired.
const directMessageRaceRounds = 50

// TestDirectMessage_OpensOnceUnderConcurrentRequests has both people open a
// conversation at the same moment, on both engines: they land in one.
func TestDirectMessage_OpensOnceUnderConcurrentRequests(t *testing.T) {
	race := func(t *testing.T, database *db.DatabaseSqlc) {
		f := newFixtureOn(t, database)
		pairs := [][2]string{{"bob", "carol"}, {"carol", "dave"}, {"dave", "bob"}}
		for round := range directMessageRaceRounds {
			// A fresh set each round: a third account joins the pair.
			pair := pairs[round%len(pairs)]
			extra, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
				Username: "extra" + string(rune('a'+round%26)) + string(rune('a'+round/26)), PasswordHash: "h", RecoveryPhraseHash: "r",
			})
			if err != nil {
				t.Fatal(err)
			}
			results := make([]chatutil.OpenDirectMessageResult, 2)
			errs := make([]error, 2)
			start := make(chan struct{})
			var done sync.WaitGroup
			for i := range 2 {
				done.Go(func() {
					<-start
					results[i], errs[i] = chatutil.OpenDirectMessage(chatutil.OpenDirectMessageParams{
						Ctx: context.Background(), Database: database, Principal: f.as(pair[i]),
						UserIDs: []int64{f.users[pair[1-i]], extra.ID},
					})
				})
			}
			close(start)
			done.Wait()
			if errs[0] != nil || errs[1] != nil || results[0].Channel.ID != results[1].Channel.ID ||
				results[0].Created == results[1].Created || len(results[0].Channel.Members) != 3 {
				t.Fatalf("round %d: %+v / %v and %+v / %v; want one conversation, made once, with 3 people",
					round, results[0], errs[0], results[1], errs[1])
			}
		}
	}

	t.Run("sqlite", func(t *testing.T) { race(t, dbtest.NewDB(t)) })
	t.Run("postgres", func(t *testing.T) {
		database, err := db.ConnectToPostgres(dbtest.PostgresURL(t))
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { database.Db.Close() })
		race(t, database)
	})
}

// TestDirectMessageEditAndTypingSkipANonMemberAdmin checks the routes and
// events #2426 added hold for a direct message: an admin outside it can't
// edit in it or say they are typing, and hears neither the edit nor the
// typing of its members.
func TestDirectMessageEditAndTypingSkipANonMemberAdmin(t *testing.T) {
	f := newFixture(t)
	f.publishKeys(t, "bob", "carol")
	dm := f.dm(t, "bob", "carol").Channel
	if _, err := f.createVersion("bob", dm.ID, 1); err != nil {
		t.Fatal(err)
	}
	posted, err := f.post("bob", dm.ID, sealedMessage(1, 1))
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	edit := func(as string, nonce byte) error {
		_, err := chatutil.EditMessage(chatutil.EditMessageParams{
			Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as(as),
			MessageID: posted.Message.ID, KeyVersion: 1, Ciphertext: sealedMessage(nonce, 2),
		})
		return err
	}
	typing := func(as string) error {
		_, err := chatutil.Typing(chatutil.TypingParams{Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as(as), ChannelID: dm.ID})
		return err
	}
	if err := edit("admin", 2); !errors.Is(err, chatutil.ErrMessageNotFound) {
		t.Errorf("EditMessage as a non-member admin = %v, want ErrMessageNotFound", err)
	}
	if err := typing("admin"); !errors.Is(err, chatutil.ErrChannelNotFound) {
		t.Errorf("Typing as a non-member admin = %v, want ErrChannelNotFound", err)
	}

	heard, stop := f.bus.Subscribe("test")
	defer stop()
	if err := edit("bob", 3); err != nil {
		t.Fatal(err)
	}
	if err := typing("carol"); err != nil {
		t.Fatal(err)
	}
	admin, err := accessutil.Load(accessutil.LoadParams{Ctx: ctx, Database: f.database, Principal: f.as("admin")})
	if err != nil {
		t.Fatal(err)
	}
	bob, err := accessutil.Load(accessutil.LoadParams{Ctx: ctx, Database: f.database, Principal: f.as("bob")})
	if err != nil {
		t.Fatal(err)
	}
	for _, kind := range []eventbus.EventKind{eventbus.EventChatMessageEdited, eventbus.EventChatTyping} {
		evt := <-heard
		if evt.Kind != kind {
			t.Fatalf("event = %s, want %s", evt.Kind, kind)
		}
		if accessutil.FilterEvent(accessutil.FilterEventParams{Access: admin.Access, Event: evt}).Deliver {
			t.Errorf("%s reaches a non-member admin", kind)
		}
		if !accessutil.FilterEvent(accessutil.FilterEventParams{Access: bob.Access, Event: evt}).Deliver {
			t.Errorf("%s misses bob", kind)
		}
	}
}

// TestDirectMessageForkIsMarked opens a bigger conversation from a direct
// message and marks it as started from an earlier one, for every member, and
// refuses a fork that drops someone or comes from a conversation the caller
// isn't in (#2423).
func TestDirectMessageForkIsMarked(t *testing.T) {
	f := newFixture(t)
	pair := f.dm(t, "bob", "carol").Channel
	fork := func(as string, from int64, with ...string) (chatutil.OpenDirectMessageResult, error) {
		ids := []int64{}
		for _, name := range with {
			ids = append(ids, f.users[name])
		}
		return chatutil.OpenDirectMessage(chatutil.OpenDirectMessageParams{
			Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as), UserIDs: ids, FromChannelID: from,
		})
	}

	if _, err := fork("dave", pair.ID, "bob", "carol"); !errors.Is(err, chatutil.ErrChannelNotFound) {
		t.Errorf("fork from a conversation dave isn't in = %v, want ErrChannelNotFound", err)
	}
	if _, err := fork("bob", pair.ID, "dave"); !errors.Is(err, chatutil.ErrDirectMessageFork) {
		t.Errorf("fork that drops carol = %v, want ErrDirectMessageFork", err)
	}
	if _, err := fork("bob", pair.ID, "carol"); !errors.Is(err, chatutil.ErrDirectMessageFork) {
		t.Errorf("fork that adds no one = %v, want ErrDirectMessageFork", err)
	}
	general := f.general(t)
	if _, err := fork("bob", general.ID, "carol", "dave"); !errors.Is(err, chatutil.ErrChannelNotFound) {
		t.Errorf("fork from a named channel = %v, want ErrChannelNotFound", err)
	}

	group, err := fork("bob", pair.ID, "carol", "dave")
	if err != nil || !group.Created || !group.Channel.Forked {
		t.Fatalf("fork = %+v, %v; want a new conversation marked as forked", group, err)
	}
	if pair.Forked {
		t.Errorf("the conversation it came from is marked as forked")
	}
	listed, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: context.Background(), Database: f.database, Principal: f.as("dave")})
	if err != nil {
		t.Fatal(err)
	}
	for _, channel := range listed.Channels {
		if channel.ID == group.Channel.ID && !channel.Forked {
			t.Errorf("dave's list doesn't mark the fork")
		}
	}

	// The same people already have it: reopening is not a fork, and a
	// conversation first opened plainly stays unmarked.
	plain := f.dm(t, "carol", "dave").Channel
	again, err := fork("carol", plain.ID, "dave", "bob")
	if err != nil || again.Created || again.Channel.ID != group.Channel.ID || !again.Channel.Forked {
		t.Errorf("reopen through a fork = %+v, %v; want the existing conversation unchanged", again, err)
	}
	trio := f.dm(t, "admin", "bob", "dave").Channel
	if trio.Forked {
		t.Errorf("a conversation opened plainly is marked as forked")
	}
}
