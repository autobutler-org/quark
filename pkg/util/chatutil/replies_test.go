package chatutil_test

import (
	"context"
	"errors"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// reply posts ciphertext as a reply in rootID's side conversation.
func (f fixture) reply(as string, channelID, rootID int64, ciphertext []byte) (chatutil.PostMessageResult, error) {
	return chatutil.PostMessage(chatutil.PostMessageParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as),
		ChannelID: channelID, KeyVersion: 1, Ciphertext: ciphertext, RootID: rootID,
	})
}

func (f fixture) replies(t *testing.T, as string, rootID int64) []int64 {
	t.Helper()
	page, err := chatutil.ListReplies(chatutil.ListRepliesParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as(as), MessageID: rootID,
	})
	if err != nil {
		t.Fatalf("ListReplies(%d) as %s: %v", rootID, as, err)
	}
	return messageIDs(page.Messages)
}

func messageIDs(messages []chatutil.Message) []int64 {
	ids := make([]int64, 0, len(messages))
	for _, m := range messages {
		ids = append(ids, m.ID)
	}
	return ids
}

// TestReplyRefusals checks each reply chatutil turns down (#4345): a root
// that is missing or in another channel, a reply to a reply, and a poll.
func TestReplyRefusals(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	other := f.keyedRoom(t, "other")
	root, err := f.post("bob", room, sealedMessage('r', 'r'))
	if err != nil {
		t.Fatal(err)
	}
	elsewhere, err := f.post("bob", other, sealedMessage('e', 'e'))
	if err != nil {
		t.Fatal(err)
	}
	branch, err := f.reply("carol", room, root.Message.ID, sealedMessage('b', 'b'))
	if err != nil {
		t.Fatal(err)
	}

	if _, err := f.reply("bob", room, elsewhere.Message.ID, sealedMessage('x', '1')); !errors.Is(err, chatutil.ErrRootNotFound) {
		t.Errorf("a root in another channel: %v, want ErrRootNotFound", err)
	}
	if _, err := f.reply("bob", room, 999999, sealedMessage('x', '2')); !errors.Is(err, chatutil.ErrRootNotFound) {
		t.Errorf("a root that doesn't exist: %v, want ErrRootNotFound", err)
	}
	if _, err := f.reply("bob", room, branch.Message.ID, sealedMessage('x', '3')); !errors.Is(err, chatutil.ErrNestedReply) {
		t.Errorf("a reply to a reply: %v, want ErrNestedReply", err)
	}
	_, err = chatutil.PostMessage(chatutil.PostMessageParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"),
		ChannelID: room, KeyVersion: 1, Ciphertext: sealedMessage('x', '4'), RootID: root.Message.ID,
		Poll: &chatutil.PollSettings{},
	})
	if !errors.Is(err, chatutil.ErrPollReply) {
		t.Errorf("a poll as a reply: %v, want ErrPollReply", err)
	}
	// dave reads nothing in room: the channel is what he can't see.
	if _, err := f.reply("dave", room, root.Message.ID, sealedMessage('x', '5')); !errors.Is(err, chatutil.ErrChannelNotFound) {
		t.Errorf("a reply from outside the channel: %v, want ErrChannelNotFound", err)
	}
	if got := f.replies(t, "bob", root.Message.ID); !slices.Equal(got, []int64{branch.Message.ID}) {
		t.Errorf("replies after the refusals = %v, want only %d", got, branch.Message.ID)
	}
}

// TestReplyUnderDeletedRoot posts into the side conversation of a deleted
// message and pages it: the tombstone keeps its branch (#4345).
func TestReplyUnderDeletedRoot(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	root, err := f.post("bob", room, sealedMessage('r', 'r'))
	if err != nil {
		t.Fatal(err)
	}
	first, err := f.reply("carol", room, root.Message.ID, sealedMessage('a', 'a'))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), MessageID: root.Message.ID,
	}); err != nil {
		t.Fatal(err)
	}
	second, err := f.reply("carol", room, root.Message.ID, sealedMessage('b', 'b'))
	if err != nil {
		t.Fatalf("a reply under a deleted root: %v", err)
	}
	if second.Message.RootID != root.Message.ID {
		t.Errorf("stored rootId = %d, want %d", second.Message.RootID, root.Message.ID)
	}
	if got := f.replies(t, "bob", root.Message.ID); !slices.Equal(got, []int64{first.Message.ID, second.Message.ID}) {
		t.Errorf("replies = %v, want %d and %d", got, first.Message.ID, second.Message.ID)
	}
}

// TestRepliesStayOutOfTheChannel checks the channel page and the unread count
// leave a side conversation's replies out, and that its own page and its
// access work like the channel's (#4345).
func TestRepliesStayOutOfTheChannel(t *testing.T) {
	ctx := context.Background()
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	root, err := f.post("bob", room, sealedMessage('r', 'r'))
	if err != nil {
		t.Fatal(err)
	}
	var branch []int64
	for _, fill := range []byte{'1', '2', '3'} {
		r, err := f.reply("bob", room, root.Message.ID, sealedMessage(fill, fill))
		if err != nil {
			t.Fatal(err)
		}
		branch = append(branch, r.Message.ID)
	}

	page, err := chatutil.ListMessages(chatutil.ListMessagesParams{Ctx: ctx, Database: f.database, Principal: f.as("carol"), ChannelID: room})
	if err != nil {
		t.Fatal(err)
	}
	if got := messageIDs(page.Messages); !slices.Equal(got, []int64{root.Message.ID}) {
		t.Errorf("channel page = %v, want only the root %d", got, root.Message.ID)
	}
	forward, err := chatutil.ListMessages(chatutil.ListMessagesParams{Ctx: ctx, Database: f.database, Principal: f.as("carol"), ChannelID: room, Forward: true})
	if err != nil {
		t.Fatal(err)
	}
	if got := messageIDs(forward.Messages); !slices.Equal(got, []int64{root.Message.ID}) {
		t.Errorf("channel page forward = %v, want only the root %d", got, root.Message.ID)
	}

	channels, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: ctx, Database: f.database, Principal: f.as("carol")})
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range channels.Channels {
		if c.ID == room && c.UnreadCount != 1 {
			t.Errorf("carol's unread count = %d, want 1: the root and none of its replies", c.UnreadCount)
		}
	}

	if got := f.replies(t, "carol", root.Message.ID); !slices.Equal(got, branch) {
		t.Errorf("replies = %v, want %v", got, branch)
	}
	older, err := chatutil.ListReplies(chatutil.ListRepliesParams{
		Ctx: ctx, Database: f.database, Principal: f.as("carol"), MessageID: root.Message.ID, Before: branch[2], Limit: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := messageIDs(older.Messages); !slices.Equal(got, branch[1:2]) {
		t.Errorf("replies before %d, limit 1 = %v, want %v", branch[2], got, branch[1:2])
	}
	newer, err := chatutil.ListReplies(chatutil.ListRepliesParams{
		Ctx: ctx, Database: f.database, Principal: f.as("carol"), MessageID: root.Message.ID, After: branch[0], Forward: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := messageIDs(newer.Messages); !slices.Equal(got, branch[1:]) {
		t.Errorf("replies after %d = %v, want %v", branch[0], got, branch[1:])
	}
	for _, as := range []string{"dave", "admin"} {
		if _, err := chatutil.ListReplies(chatutil.ListRepliesParams{
			Ctx: ctx, Database: f.database, Principal: f.as(as), MessageID: root.Message.ID,
		}); !errors.Is(err, chatutil.ErrMessageNotFound) {
			t.Errorf("ListReplies as %s: %v, want ErrMessageNotFound", as, err)
		}
	}
}

// TestReplyEventsCarryRoot checks chat_message_created, edited and deleted
// name a reply's root, so a client keeps it out of the channel (#4345).
func TestReplyEventsCarryRoot(t *testing.T) {
	ctx := context.Background()
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	root, err := f.post("bob", room, sealedMessage('r', 'r'))
	if err != nil {
		t.Fatal(err)
	}
	events, unsubscribe := f.bus.Subscribe("reply-events-test")
	defer unsubscribe()

	reply, err := f.reply("bob", room, root.Message.ID, sealedMessage('a', 'a'))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := chatutil.EditMessage(chatutil.EditMessageParams{
		Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("bob"),
		MessageID: reply.Message.ID, KeyVersion: 1, Ciphertext: sealedMessage('b', 'b'),
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
		Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("bob"), MessageID: reply.Message.ID,
	}); err != nil {
		t.Fatal(err)
	}
	for _, kind := range []eventbus.EventKind{eventbus.EventChatMessageCreated, eventbus.EventChatMessageEdited, eventbus.EventChatMessageDeleted} {
		evt := <-events
		changed, ok := evt.Data.(eventbus.ChatMessageChanged)
		if evt.Kind != kind || !ok || changed.MessageID != reply.Message.ID || changed.RootID != root.Message.ID {
			t.Errorf("event = %s %+v, want %s for %d under root %d", evt.Kind, evt.Data, kind, reply.Message.ID, root.Message.ID)
		}
	}
}

// TestRepliesInAnonymousChannel checks a side conversation in an anonymous
// channel (#2949) names its authors by pseudonym, on the post and on its
// page, as the channel's own messages do.
func TestRepliesInAnonymousChannel(t *testing.T) {
	ctx := context.Background()
	f := newFixture(t)
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
	if _, err := f.putChannelKeys("bob", room.ID, 'B'); err != nil {
		t.Fatal(err)
	}
	carol, err := f.putChannelKeys("carol", room.ID, 'C')
	if err != nil {
		t.Fatal(err)
	}
	own := anonGrant('B', room.ID, 1, room.SelfID, 9)
	if _, err := chatutil.CreateKeyVersion(chatutil.CreateKeyVersionParams{
		Ctx: ctx, Database: f.database, EventBus: f.bus, Principal: f.as("bob"), ChannelID: room.ID, Version: 1,
		SealedKey: own.SealedKey, Signature: own.Signature,
	}); err != nil {
		t.Fatal(err)
	}
	root, err := f.post("bob", room.ID, sealedMessage('r', 'r'))
	if err != nil {
		t.Fatal(err)
	}
	posted, err := f.reply("carol", room.ID, root.Message.ID, sealedMessage('a', 'a'))
	if err != nil {
		t.Fatal(err)
	}
	if posted.Message.AuthorID != carol.SelfID {
		t.Errorf("posted reply's authorId = %d, want carol's pseudonym %d", posted.Message.AuthorID, carol.SelfID)
	}
	page, err := chatutil.ListReplies(chatutil.ListRepliesParams{Ctx: ctx, Database: f.database, Principal: f.as("bob"), MessageID: root.Message.ID})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Messages) != 1 || page.Messages[0].AuthorID != carol.SelfID {
		t.Errorf("replies = %+v, want one by carol's pseudonym %d", page.Messages, carol.SelfID)
	}
}
