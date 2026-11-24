package chatutil_test

import (
	"context"
	"testing"

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
