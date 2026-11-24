package chatutil_test

import (
	"context"
	"errors"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// branchOf is the Branch on rootID in carol's page of the channel.
func (f fixture) branchOf(t *testing.T, channelID, rootID int64) *chatutil.Branch {
	t.Helper()
	page, err := chatutil.ListMessages(chatutil.ListMessagesParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channelID,
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range page.Messages {
		if m.ID == rootID {
			return m.Branch
		}
	}
	t.Fatalf("root %d is not in the page", rootID)
	return nil
}

// nextBranchEvent is the next chat_branch_changed on events.
func nextBranchEvent(t *testing.T, events <-chan eventbus.Event) eventbus.ChatBranchChanged {
	t.Helper()
	for evt := range events {
		if evt.Kind == eventbus.EventChatBranchChanged {
			return evt.Data.(eventbus.ChatBranchChanged)
		}
	}
	t.Fatal("the bus closed before chat_branch_changed")
	return eventbus.ChatBranchChanged{}
}

// TestBranchSummary posts and deletes replies and checks the root's branch in
// the channel page and the chat_branch_changed each one sends (#4346): a post
// raises the count and moves lastReplyAt, a delete lowers it, and deleting
// the last live reply removes the branch.
func TestBranchSummary(t *testing.T) {
	ctx := context.Background()
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	root, err := f.post("bob", room, sealedMessage('r', 'r'))
	if err != nil {
		t.Fatal(err)
	}
	if branch := f.branchOf(t, room, root.Message.ID); branch != nil {
		t.Fatalf("branch before any reply = %+v, want none", branch)
	}
	events, unsubscribe := f.bus.Subscribe("branch-summary-test")
	defer unsubscribe()

	var replies []chatutil.Message
	for i, fill := range []byte{'a', 'b'} {
		reply, err := f.reply("carol", room, root.Message.ID, sealedMessage(fill, fill))
		if err != nil {
			t.Fatal(err)
		}
		replies = append(replies, reply.Message)
		want := int64(i + 1)
		branch := f.branchOf(t, room, root.Message.ID)
		if branch == nil || branch.ReplyCount != want || !branch.LastReplyAt.Equal(reply.Message.CreatedAt) {
			t.Errorf("branch after reply %d = %+v, want %d replies, last at %v", i+1, branch, want, reply.Message.CreatedAt)
		}
		evt := nextBranchEvent(t, events)
		if evt.ChannelID != room || evt.MessageID != root.Message.ID || evt.ReplyCount != want ||
			evt.LastReplyAt == nil || !evt.LastReplyAt.Equal(reply.Message.CreatedAt) {
			t.Errorf("event after reply %d = %+v, want %d replies on %d", i+1, evt, want, root.Message.ID)
		}
	}

	del := func(id int64) {
		t.Helper()
		if _, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
			Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("carol"), MessageID: id,
		}); err != nil {
			t.Fatal(err)
		}
	}
	del(replies[1].ID)
	branch := f.branchOf(t, room, root.Message.ID)
	if branch == nil || branch.ReplyCount != 1 || !branch.LastReplyAt.Equal(replies[0].CreatedAt) {
		t.Errorf("branch after deleting the newest = %+v, want 1 reply, last at %v", branch, replies[0].CreatedAt)
	}
	if evt := nextBranchEvent(t, events); evt.ReplyCount != 1 || evt.LastReplyAt == nil || !evt.LastReplyAt.Equal(replies[0].CreatedAt) {
		t.Errorf("event after deleting the newest = %+v, want 1 reply", evt)
	}

	del(replies[0].ID)
	if branch := f.branchOf(t, room, root.Message.ID); branch != nil {
		t.Errorf("branch after deleting every reply = %+v, want none", branch)
	}
	if evt := nextBranchEvent(t, events); evt.MessageID != root.Message.ID || evt.ReplyCount != 0 || evt.LastReplyAt != nil {
		t.Errorf("event after deleting every reply = %+v, want 0 replies and no lastReplyAt", evt)
	}
}

// TestListBranches pages a channel's side conversations on both engines
// (#4351): newest last reply first across a page boundary, a deleted root
// still listed, a branch whose replies are all deleted gone, and a quiet
// branch back on top once it gets a reply. A non-member admin of a direct
// message can't list its branches.
func TestListBranches(t *testing.T) {
	run := func(t *testing.T, database *db.DatabaseSqlc) {
		ctx := context.Background()
		f := newFixtureOn(t, database)
		room := f.keyedRoom(t, "room")
		fill := byte(0)
		post := func(as string, rootID int64) int64 {
			t.Helper()
			fill++
			var posted chatutil.PostMessageResult
			var err error
			if rootID == 0 {
				posted, err = f.post(as, room, sealedMessage(fill, fill))
			} else {
				posted, err = f.reply(as, room, rootID, sealedMessage(fill, fill))
			}
			if err != nil {
				t.Fatal(err)
			}
			return posted.Message.ID
		}
		del := func(id int64) {
			t.Helper()
			if _, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
				Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("bob"), MessageID: id,
			}); err != nil {
				t.Fatal(err)
			}
		}
		list := func(as string, before, limit int64) (chatutil.ListBranchesResult, error) {
			return chatutil.ListBranches(chatutil.ListBranchesParams{
				Ctx: ctx, Database: f.database, Principal: f.as(as), ChannelID: room, Before: before, Limit: limit,
			})
		}
		// pages lists every branch a page of two at a time.
		pages := func() []int64 {
			t.Helper()
			ids := []int64{}
			for before := int64(0); ; {
				page, err := list("carol", before, 2)
				if err != nil {
					t.Fatal(err)
				}
				for _, m := range page.Messages {
					if m.Branch == nil || m.Branch.ReplyCount == 0 {
						t.Errorf("branch %d listed without a summary: %+v", m.ID, m.Branch)
					}
				}
				ids = append(ids, messageIDs(page.Messages)...)
				if page.NextBefore == 0 {
					return ids
				}
				before = page.NextBefore
			}
		}

		// A root with no reply is never listed.
		quiet, gone, deletedRoot, busy, _ := post("bob", 0), post("bob", 0), post("bob", 0), post("bob", 0), post("bob", 0)
		post("carol", quiet)
		del(post("carol", gone))
		post("carol", deletedRoot)
		del(deletedRoot)
		post("carol", busy)
		post("bob", busy)

		if got, want := pages(), []int64{busy, deletedRoot, quiet}; !slices.Equal(got, want) {
			t.Errorf("branches = %v, want %v", got, want)
		}
		page, err := list("carol", 0, 2)
		if err != nil {
			t.Fatal(err)
		}
		if b := page.Messages[0].Branch; b.ReplyCount != 2 || !b.Involved || b.UnreadCount != 1 {
			t.Errorf("busy branch for carol = %+v, want 2 replies, involved, 1 unread", b)
		}
		if root := page.Messages[1]; root.DeletedAt == nil {
			t.Errorf("deleted root = %+v, want a tombstone", root)
		}

		post("bob", quiet)
		if got, want := pages(), []int64{quiet, busy, deletedRoot}; !slices.Equal(got, want) {
			t.Errorf("branches after a new reply = %v, want %v", got, want)
		}

		dm := f.dm(t, "bob", "carol").Channel
		if _, err := chatutil.ListBranches(chatutil.ListBranchesParams{
			Ctx: ctx, Database: f.database, Principal: f.as("admin"), ChannelID: dm.ID,
		}); !errors.Is(err, chatutil.ErrChannelNotFound) {
			t.Errorf("a non-member admin listing a direct message's branches = %v, want ErrChannelNotFound", err)
		}
	}

	t.Run("sqlite", func(t *testing.T) { run(t, dbtest.NewDB(t)) })
	t.Run("postgres", func(t *testing.T) {
		database, err := db.ConnectToPostgres(dbtest.PostgresURL(t))
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { database.Db.Close() })
		run(t, database)
	})
}
